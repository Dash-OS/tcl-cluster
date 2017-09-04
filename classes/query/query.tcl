

::oo::class create ::cluster::query {}

::oo::define ::cluster::query {
  variable CLUSTER QUERY_ID COMMAND TIMEOUT_ID SERVICES
  variable SERVICE PAYLOAD PAYLOADS QUERY CHANNEL RESULTS PROPS
}

::oo::define ::cluster::query constructor {cluster args} {
  set CLUSTER  $cluster

  if { [dict exists $args -collect] && [dict get $args -collect] } {

    # Collect the results of each event and return to the done event
    # We do this if RESULTS exists
    set RESULTS [dict create]
  }

  set QUERY_ID [dict get $args -id]

  if { ! [dict exists $args -resolve] && ! [dict exists $args -resolver] } {
    throw CLUSTER_QUERY_NO_RESOLVE "You must provide a -resolve property to your query"
  }

  if { [dict exists $args -resolve] } {
    lappend SERVICES {*}[$CLUSTER resolve [dict get $args -resolve]]
  }
  if { [dict exists $args -resolver] } {
    lappend SERVICES {*}[$CLUSTER resolver {*}[dict get $args -resolver]]
  }

  if { $SERVICES eq {} } {
    throw CLUSTER_QUERY_NO_SERVICES "No Services found with [dict get $args -resolve]"
  }

  if { [dict exists $args -props] } {
    set PROPS [dict get $args -props]
  } else {
    set PROPS {}
  }

  if { ! [dict exists $args -query] } {
    throw CLUSTER_QUERY_NO_QUERY "No Query was provided with the query request"
  } else { set QUERY [dict get $args -query] }

  if { ! [dict exists $args -command] } {
    throw CLUSTER_QUERY_NO_COMMAND "You must provide a -command to trigger with any responses"
  } else { set COMMAND [dict get $args -command] }

  # Should we broadcast the query using filters?
  if { [dict exists $args -broadcast] && [dict get $args -broadcast] } {
    set broadcast 1
    set CHANNEL   0
  } elseif { [dict exists $args -channel] } {
    set broadcast 0
    set CHANNEL   [dict get $args -channel]
  } else {
    set broadcast 0
    set CHANNEL   0
  }

  if { [dict exists $args -protocols] } {
    set protocols [dict get $args -protocols]
  } else { set protocols {} }

  # We always have a timeout value included.  This is how long we will keep our
  # query handler alive before removing it.  Any services which reply after the
  # timeout will be ignored.
  if { ! [dict exists $args -timeout] } {
    set TIMEOUT_ID [after 30000 [namespace code [list my timeout]]]
  } else {
    set TIMEOUT_ID [after [dict get $args -timeout] [namespace code [list my timeout]]]
  }

  set filter [lmap e $SERVICES { $e sid }]

  set payload [$CLUSTER query_payload $QUERY_ID $QUERY $filter $CHANNEL]

  if { $broadcast } {
    $CLUSTER broadcast $payload
  } else {
    foreach service $SERVICES {
      set protocol [ $service send $payload $protocols 0 ]
    }
  }

  my DispatchEvent start
}

::oo::define ::cluster::query destructor {
  after cancel $TIMEOUT_ID
  my DispatchEvent done
  catch { $CLUSTER query_done $QUERY_ID }
}

::oo::define ::cluster::query method event { ns args } {
  switch -- $ns {
    response {
      lassign $args SERVICE PAYLOAD
      dict set PAYLOADS $SERVICE $PAYLOAD
      set SERVICES [lsearch -all -inline -not -exact $SERVICES $SERVICE]
      if { [dict exists $PAYLOAD error] } {
        my DispatchEvent error
      } else { my DispatchEvent response }
      if { $SERVICES eq {} } { [self] destroy }
    }
  }
}

::oo::define ::cluster::query method remaining {} { return $SERVICES }
::oo::define ::cluster::query method service   {} { return $SERVICE  }
::oo::define ::cluster::query method payload   {} { return $PAYLOAD  }
::oo::define ::cluster::query method payloads  {} { return $PAYLOADS }
::oo::define ::cluster::query method query     {} { return $QUERY    }
::oo::define ::cluster::query method channel   {} { return $CHANNEL  }
::oo::define ::cluster::query method props     {} { return $PROPS    }

::oo::define ::cluster::query method results   {} {
  if { [info exists RESULTS] } { return $RESULTS } else {
    throw CLUSTER_QUERY_NO_COLLECT "You may only get \"results\" of a cluster query if the -collect argument is specified"
  }
}

::oo::define ::cluster::query method data {} {
  tailcall [namespace code [list my result]]
}

::oo::define ::cluster::query method result {} {
  if { [dict exists $PAYLOAD data] } {
    return [dict get $PAYLOAD data]
  }
}
::oo::define ::cluster::query method error {} {
  if { [dict exists $PAYLOAD error] } {
    return [dict get $PAYLOAD error]
  }
}
::oo::define ::cluster::query method timeout {} {
  after cancel $TIMEOUT_ID
  my DispatchEvent timeout
  [self] destroy
}

# break - kill our query and stop parsing responses
::oo::define ::cluster::query method DispatchEvent { event } {
  set code [catch { uplevel #0 [list {*}$COMMAND [list $event [self]]] } result]
  switch -- $code {
    0 - 3 - 4 { # OK - BREAK - CONTINUE
      if { [info exists RESULTS] && $event ni [list done start timeout] } {
        # We are collecting the results that are returned and will have them available
        # as a dict that can be requested throughout the lifecycle.
        dict set RESULTS $SERVICE [dict create \
          event  $event \
          result $result
        ]
      }
      if { $code == 3 } {
        if { ! [string equal $event done] } { [self] destroy }
      }
    }
    1 { # ERROR
      ::onError $result {} "While Parsing Cluster Query Event $event" [self]
    }
    2 { # RETURN

    }
  }
}
