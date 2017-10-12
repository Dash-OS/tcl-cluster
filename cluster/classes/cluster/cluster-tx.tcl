# Broadcast to the cluster.  This is a shortcut to send to the cluster protocol.
::oo::define ::cluster::cluster method broadcast { payload } {
  try {
    set proto [dict get $PROTOCOLS c]
    try {my run_hook broadcast} on error {r} { return 0 }
    try {my run_hook channel [dict get $payload channel] send} on error {r} { return 0 }
    return [$proto send [::cluster::packet::encode $payload]]
  } on error {result options} {
    ::onError $result $options "While Broadcasting a Cluster Payload" $payload
  }
}

# We send a heartbeat to the cluster at the given interval.  Any listening services
# will reset their timers for our service as they know we still exist.
::oo::define ::cluster::cluster method heartbeat { {props {}} {tags 0} {channel 0} } {
  try {
    if { $channel == 0 } {
      # We only reset the heartbeat timer when broadcasting our heartbeat
      after cancel $AFTER_ID
      set AFTER_ID [ after [dict get $CONFIG heartbeat] [namespace code [list my heartbeat]] ]
      # Build the payload for the broadcast heartbeat - be sure we broadcast any updated
      # props to the cluster.
      set props [lsort -unique [concat $UPDATED_PROPS $props]]
      set UPDATED_PROPS [list]
      my CheckServices
      my CheckProtocols
    }
    if { "tags" in $props } { set tags 1 }
    my broadcast [my heartbeat_payload $props $tags $channel]
  } on error {result options} {
    ::onError $result $options "While sending a cluster heartbeat"
  }
}

# Reschedule the heartbeat so that it will occur after the given time.  This is useful
# for when we want to cause a heartbeat to occur sooner than the normal time but dont
# want to accidentally dispatch tons of heartbeats when multiple services call it, etc.
::oo::define ::cluster::cluster method heartbeat_after { ms } {
  try {
    after cancel $AFTER_ID
    set AFTER_ID [ after $ms [namespace code [list my heartbeat]] ]
  } on error {result options} {
    ::onError $result $options "While scheduling a cluster heartbeat"
  }
}


# Send a discovery probe to the cluster.  Each service will send its response
# based on the best protocol it can find.
::oo::define ::cluster::cluster method discover { {ruid {}} {channel 0} } {
  my variable LAST_DISCOVERY
  if { ! [info exists LAST_DISCOVERY] } { set LAST_DISCOVERY [clock seconds] } else {
    set now [clock seconds]
    if { ( $now - $LAST_DISCOVERY ) <= 30 } {
      # We do not allow discovery more than once for every 30 seconds.
      return 0
    } else { set LAST_DISCOVERY $now }
  }
  return [ my broadcast [ my discovery_payload [list protoprops] 1 $channel ] ]
}

# $cluster send \
#   -resolve   [list] \
#   -resolver  [list] \
#   -services  [list] \
#   -filter    [list] \
#   -protocols [list] \
#   -channel   0 \
#   -ruid      {} \
#   -data      {}

::oo::define ::cluster::cluster method send { args } {
  set request [dict create]
  if { [dict exists $args -services] } {
    # A list of services to send to was provided directly
    set services [dict get $args -services]
  } else { set services [list] }
  if { [dict exists $args -resolver] } {
    # Use the advanced resolver to discover the services to send to.
    lappend services {*}[my resolver [dict get $args -resolver]]
  }
  if { [dict exists $args -resolve] } {
    # Resolve the given list.
    lappend services {*}[my resolve [dict get $args -resolve]]
  }

  #puts "Send to services [llength $services]"
  #puts $services
  set allow_broadcast 0

  if { [dict exists $args -broadcast] } {
    # 1 / 0 - Indicates if we want to broadcast the message or not.
    # If empty we will try to decide automatically.
    set broadcast [dict get $args -broadcast]
    if { $broadcast eq {} } { set allow_broadcast 1 }
  } else {
    # When broadcast is empty we are indicating that we are not yet
    # sure if we want to broadcast the message.
    set broadcast {}
    # When we have not explicitly turned broadcasting off then we
    # will allow it to be used as a last resort if all other protocols
    # fail.  The broadcast will be filtered so only the given service
    # will respond.
    set allow_broadcast 1
  }

  if { ! [string is true -strict $broadcast] } {
    if { $services eq {} } { return }
  }

  if { [dict exists $args -protocols] } {
    set protocols [dict get $args -protocols]
  } else {
    # If protocols isnt provided - we need to determine the
    # best way to send our message based on the number of
    # services that have been resolved.
    #
    # Right now we keep it simple - more than 3 we use cluster
    # otherwise we use default.
    #
    # This can be overridden by providing the -broadcast argument
    # which can force us to broadcast the message with a filter
    # when desired.
    if { [string is true -strict $broadcast] } {
      set protocols c
    } elseif { $broadcast eq {} && [llength $services] > 3 } {
      set protocols c
      set broadcast 1
    } else {
      # Use each services preferred method.
      set protocols {}
      # We will not broadcast unless needed - but it may still
      # be allowed if all-else fails for a service.  This simply
      # indicates that we would like to first try the other protocols.
      set broadcast 0
    }
  }

  if { [dict exists $args -channel] } {
    set channel [dict get $args -channel]
  } else {
    set channel 0
  }

  if { [dict exists $args -ruid] } {
    dict set request ruid [dict get $args -ruid]
  }

  if { [dict exists $args -data] } {
    dict set request data [dict get $args -data]
  }

  # Make sure we only have one of each service
  set services [lsort -unique $services]

  if { [string is true -strict $broadcast] && $services ne {} } {
    # If we are using the cluster protocol to transmit, we use broadcast
    # to send our payload.  This means that we also need to add a filter
    # to the request so that only our desired services will handle the
    # message being sent.
    #
    # A filter will be automatically applied when sending directly to
    # a service otherwise.
    #
    # This allows us to use the multicast as a p2p connection to aid in
    # self healing and protocol negotiation when all else fails.
    set filter [list]
    foreach service $services {
      lappend filter [$service sid]
    }
    dict set request filter $filter
  }

  set payload [my event_payload $request $channel]

  if { [string is true -strict $broadcast] } {
    # We have indicated that we want to broadcast the message.
    my broadcast $payload
  } else {
    # We need to send to each service.  We will examine the result and use it
    # to determine how to proceed.  We will not allow broadcasts with this command
    # as we will attempt to handle it ourselves if required.
    set response [my send_payload $services $payload $protocols 0]
    ~! "Response" "Cluster Send Response" -context $response
    if { $response eq {} } {
      # We will receive an empty response when a hook has cancelled the
      # transmission
    } else {
      lassign $response success failed
      # puts stderr "Success: $success"

      if { $failed ne {} } {
        #puts stderr "Failed:  $failed"
        # If we failed to send to any services we will determine how we should
        # proceed.
        # ::utils::flog "Failed to Send To Cluster Services \n $args \n $failed"
        # ~! "Cluster Warning" "Failed to send to Cluster Services" \
        #   -context "
        #     Success:
        #     $success
        #     ------------
        #     Failed:
        #     $failed
        #   "
      }
    }
  }
  # Return a resolved list of the services and payload being used.  This way
  # multiple requests can simply call send_payload directly without running
  # through this process.
  return [list $services $payload $protocols]
}

::oo::define ::cluster::cluster method send_payload { services payload protocols {allow_broadcast 0} } {
  set success [dict create]
  set failed  [dict create]

  try {my run_hook channel [dict get $payload channel] send} on error { r } { return }

  foreach service $services {
    try {
      set result [$service send $payload $protocols $allow_broadcast]
      if { $result eq {} } {
        dict set failed $service  [dict create status fail result negotiation_failure]
      } else {
        dict set success $service [dict create status ok result $result]
      }
    } on error {result} {
      dict set failed $service [dict create status error result $result]
    }
  }
  return [list $success $failed]
}
