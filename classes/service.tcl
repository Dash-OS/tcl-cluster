
# Each service that is discovered will have an object created which manages
# its lifecycle.
#
#
::oo::define ::cluster::service {
  variable CLUSTER UUID CHANNELS
  variable LAST_HEARTBEAT PROPS 
  variable PROTOCOLS FLAGS SERVICE_ID SYSTEM_ID
  variable SOCKETS ADDRESS TAGS LOCAL RESOLVER
  variable NEW
}

::oo::define ::cluster::service constructor { cluster proto chanID payload descriptor } {
  # Save a reference to our parent cluster so that we can communicate with it as necessary.
  set CLUSTER $cluster
  # PROPS stores the services properties.  This will include things such as 
  # "tags", "protocol properties", etc.  They are provided via heartbeat and/or
  # discovery requests.  When props are received, they are merged into the previous
  # properties unless we receive a FLUSH request (7).
  set PROPS [dict create]
  
  set SERVICE_ID [dict get $payload sid]
  set SYSTEM_ID  [dict get $payload hid]
  set CHANNELS   [list 0]
  set PROTOCOLS  [dict get $payload protocols]
  set SOCKETS    [dict create]
  set TAGS       [list]
  set ADDRESS    [dict get $descriptor address]
  set NEW        1
  if { [dict exists $descriptor local] } {
    set LOCAL [dict get $descriptor local] 
  } else { set LOCAL [$CLUSTER is_local $ADDRESS] }
  my SetResolve
  # Confirm that we can validate this service using our standard validate method.  This is called
  # directly by the cluster before parsing any payload after we have been created initially.
  if { ! [my validate $proto $chanID $payload $descriptor] } { throw error "Failed to Validate Discovered Service" }
}

::oo::define ::cluster::service destructor {
  # Cleanup any sockets which have been opened for this service.  
  try {
    dict for { protocol chanID } $SOCKETS {
      set proto [$CLUSTER protocol $protocol]
      $proto done [self] $chanID 0
    }
    # Report the service being lost to the cluster
    $CLUSTER service_lost [self]
  } on error {result options} {
    ::onError $result $options "While Removing a Cluster Service"
  }
}

::oo::define ::cluster::service method heartbeat { {data {}} } {
  set LAST_HEARTBEAT [clock seconds]
  if { $data ne {} } {
    set PROPS [dict merge $PROPS $data] 
  }
  my variable SERVICE_EXPECTED
  if { [info exists SERVICE_EXPECTED] } {
    # If we are expecting a service and hear back from it, we will cancel 
    # any pings that we may have scheduled for the service.
    $CLUSTER cancel_service_ping [my sid]
    unset SERVICE_EXPECTED
  }
}

# opt = has (default), not, some
# modifier = equal, match, regex
::oo::define ::cluster::service method resolver { tags {modifier equal} {opt has} } {
  switch -- $opt {
    all - has {
      # Must match every tag
      foreach tag $tags { if { ! [my resolve $tag $modifier] } { return 0 } }
    }
    not {
      # Must not match any of the tags
      foreach tag $tags { if { [my resolve $tag $modifier] } { return 0 } }
    }
    some {
      # Must have at least one $what
      foreach tag $tags { if { [my resolve $tag $modifier] } { return 1 } }
    }
  }
  return 0
}

::oo::define ::cluster::service method resolve { tag {modifier equal} } { 
  switch -- $modifier {
    equal { return [expr { $tag in $RESOLVER }] }
    match { 
      foreach resolve $RESOLVER {
        if { [string match $tag $resolve] } { return 1 }
      }
    }
    regex {
      # Not Finished
    }
  }
  return 0
}

::oo::define ::cluster::service method SetResolve {} {
  set RESOLVER [list {*}$TAGS [my hid] [my sid] [my ip]]
  if { [my local] } { lappend RESOLVER "localhost" }
}

::oo::define ::cluster::service method query { args } {
  set query [lindex $args end]
  set ruid  [lindex $args end-1]
  set args  [lrange $args 0 end-2]
  if { [dict exists $args -timeout] } {
    
  }
  # We send a query payload to the service while also including 
  # a filter so we can be sure only the service we are expecting 
  # will receive the query.
  my send [$CLUSTER query_payload $ruid $query [my sid]]
}

::oo::define ::cluster::service method send { payload {protocols {}} {allow_broadcast 1} } {
  if { $protocols eq {} } { set protocols $PROTOCOLS }
  # Encode the packet that we want to send to the cluster.
  set packet [::cluster::packet::encode $payload]
  set sent   {}
  set attempts [list]
  #puts "Send to [self]"
  foreach protocol $protocols {
    if { $protocol in $attempts } { continue }
    # We attempt to send to each protocol defined.  If our send returns true, we
    # expect the send was successful and return the protocol that was used for the
    # communication.
    #
    # We include a reference to the protocol to ourselves so it can query any
    # information necessary to complete the request.
    if { $protocol ni $PROTOCOLS } {
      # Requested a protocol which this service does not say that it supports.
      # We will simply ignore it for now
      continue
    } elseif { $protocol eq "c" && ! $allow_broadcast } {
      # When we have specified that we should not broadcast we skip the cluster
      # protocol
      continue
    }
    
    # Obtain the reference for the protocol from our $cluster if it exists.
    set proto [$CLUSTER protocol $protocol]
    
    if { $proto eq {} } { 
      # This protocol is not supported by our local service.  We will move on to
      # the next one.
      continue
    }
    
    if { ! $LOCAL } {
      # Some protocols are local-only.  We need to check if this is the case and
      # skip the protocol if this service is not local to the system.
      set descriptor [$proto descriptor]
      if { [dict exists $descriptor local] && [dict get $descriptor local] } {
        continue
      }
    }
    
    if { [$proto send $packet [self]] } { return $protocol } else { lappend attempts $protocol }
  }
  
  # We were unable to send to a service that was requested.  It is possible the service no longer
  # exists.  When this occurs we broadcast a public ping of the service to indicate to the other
  # members that it may no longer exist.  This way we can cleanup services before the TTL period
  # ends and reduce false resolutions during queries.
  if { [llength $attempts] > 0 && [ my expected ] } {
    # We only schedule a ping in the case we havent heard from the service for awhile
    # or we are not already expecting a service to respond with a ping due to a previous
    # ping request from ourselves or another member.
    $CLUSTER schedule_service_ping [my sid]
  }
  
  # If none of the attempted protocols were successful, we return an empty value
  # to the caller.
  #puts "Failed to Send to Service: [self] [string bytelength $packet]"
  return
}

::oo::define ::cluster::service method receive { proto chanID payload descriptor } {
  #puts "[self] receives from $proto - $chanID"
  set data {}
  set protocol [$proto proto]
  dict with payload {}
  puts "Receiving on Channel: $channel"
  # Did our partner provide us with a request uid?  If so, any reply will include the
  # ruid so it can identify the request.
  if { [info exists ruid] } { dict set response ruid $ruid } else { set response {} }
  
  # Did our partner request that we keep the channel alive?  If the property exists, we will
  # send it with any reply that may be sent.
  if { ! [info exists keepalive] } { 
    set keepalive 0 
  } else { dict set response keepalive $keepalive }
  
  switch -- $type {
    0 {
      # Disconnect
      ~ "SERVICE [self] DISCONNECTING"
      [self] destroy
    }
    1 {
      # Beacon
      my heartbeat $data
    }
    2 {
      # Discovery
      # When we receive a discovery request from the service, we also treat it
      # as-if it were a heartbeat.  The payload of heartbeats and discovery 
      # conform to the same payloads (their properties).  Which we expect
      # will be merged with other properties we have received from the service.
      my heartbeat $data
      # Once we have processed the heartbeat and the data that came with it,
      # we will respond to the discovery request.  We will use the protocol
      # data that we have received from the service to open a channel directly
      # rather than broadcasting on every discovery request.
      my send [$CLUSTER heartbeat_payload [list protoprops] 1 0 $response]
    }
    3 {
      # Ping Requested by Service
      # When we receive this from the service it means that at least one member
      # of the cluster and this service are having an issue communicating.  It's
      # payload indicates the services which it is requesting a response from.  
      #
      # All cluster members should reduce the TTL of the given services when they
      # receive this so that the service will be terminated within the next 
      # ___ seconds.
      if { $data ne {} } { $CLUSTER expect_services $data }
    }
    4 {
      # Query
      set context [dict merge $payload [dict create \
        protocol $protocol
      ]]
      try {
        dict set response data [my hook $payload query]
      } on error {r} { dict set response error $r }
      my send [$CLUSTER response_payload $response $channel] $protocol
    }
    5 {
      # Response
      # When a service provides us with a response to a query we will attempt to
      # call the query objects event method with a reference to our service.
      #
      # If the query has already timed out, not will happen.
      my heartbeat
      if { ! [info exists ruid] } { return }
      $CLUSTER query_response [self] $payload
      # Close the connection automatically after giving our response
      set keepalive 0
    }
    6 {
      # Event
    }
    7 {
      # Flush Props / Replace with received data
      set PROPS $data
    }
  }
  if { [info exists NEW] } {
    unset NEW
    # After 1 second, call our service_discovered hook.  We provide a slight
    # delay because some services will send details about themselves after their
    # initial heartbeat.
    after 1000 [namespace code [list my hook $payload service discovered]]
  }
  $proto done [self] $chanID $keepalive
}

::oo::define ::cluster::service method hook { context args } {
  set service [self]
  set cluster $CLUSTER
  dict with context {}
  return [$CLUSTER run_hook {*}$args]
}

# When we receive a payload from what appears to be the service, we will validate
# against the service to determine if we should accept the payload or not.  We
# return true/false based on the result.
::oo::define ::cluster::service method validate { proto chanID payload descriptor } {
  dict with payload {}
  
  if { ! [info exists channel] || ! [info exists type] } { return 0 }
  if { ! [info exists protocols] || "c" ni $protocols  } { return 0 }
  if { ! [info exists sid] || ! [info exists hid] } { return 0 }
  if { $sid ne $SERVICE_ID || $hid ne $SYSTEM_ID  } { return 0 }
  
  set PROTOCOLS $protocols
  if { [dict get $descriptor address] ne $ADDRESS } {
    set ADDRESS [dict get $descriptor address]
    if { [dict exists $descriptor local] } {
      set LOCAL [dict get $descriptor local] 
    } else { set LOCAL [$CLUSTER is_local $ADDRESS] }
  }
  if { [info exists tags] } { 
    if { $tags ne $TAGS } { 
      set TAGS $tags
      my SetResolve
    }
  }
  set prevChan [my socket [$proto proto]]
  if { $prevChan ne $chanID } { my ChannelEvent open $proto $chanID }
  
  switch -- $channel {
    0 {
      # Broadcast - We always accept this
    }
    1 {
      # System - We only accept from localhost
      if { ! $LOCAL } { return 0 }
    }
    2 {
      # LAN - Need to determine if this is coming from a Local Area Network client
      puts "TO DO : ADD LAN CHANNEL!"
      return 0
    }
    default {
      # Received a Channel Message from Service : How do these rules work?
    }
  }

  return 1
}

#$service event channel close $protocol $chanID
::oo::define ::cluster::service method event { ns args } {
  switch -nocase -glob -- $ns {
    ch* - channel {
      lassign $args action proto chanID
      my ChannelEvent $action $proto $chanID
    }
  }
}

::oo::define ::cluster::service method ChannelEvent { action proto chanID } {
  set protocol [$proto proto]
  switch -nocase -glob -- $action {
    cl* - close {
      if { [dict exists $SOCKETS $protocol] && [dict get $SOCKETS $protocol] eq $chanID } {
        dict unset SOCKETS $protocol
      }
    }
    op* - open {
      if { [dict exists $SOCKETS $protocol] && [dict get $SOCKETS $protocol] ne $chanID } {
        # A new channel is opening but we still have a reference to an older one?
        # We only allow one socket to each service per protocol - we call done on the previous
        $proto done [self] [dict get $SOCKETS $protocol] 0
      }
      dict set SOCKETS $protocol $chanID
    }
  }
}

# When we determine a service may no longer exist on the cluster, but did not 
# exit gracefully, this will be called on the service.  This means that the 
# service has been requested to report itself to the cluster or else it will 
# be removed from the cluster.
::oo::define ::cluster::service method expected { {within 30} } {
  my variable SERVICE_EXPECTED
  if { [my last_seen] < 3 || [info exists SERVICE_EXPECTED] } {
    # If the service was last seen within the last 3 seconds, we will ignore this.
    return 0
  }
  set SERVICE_EXPECTED 1
  set NEW_HEARTBEAT [expr { [clock seconds] - [$CLUSTER ttl] + $within }]
  if { $NEW_HEARTBEAT < $LAST_HEARTBEAT } { set LAST_HEARTBEAT $NEW_HEARTBEAT }
  return 1
}

::oo::define ::cluster::service method socket { protocol } { 
  if { [dict exists $SOCKETS $protocol] } {
    return [dict get $SOCKETS $protocol] 
  }
}

::oo::define ::cluster::service method info {} {
  return [dict create \
    last_seen  [my last_seen] \
    address    $ADDRESS \
    props      $PROPS \
    system_id  $SYSTEM_ID \
    service_id $SERVICE_ID \
    tags       $TAGS
  ]
}

# Our objects accessors
::oo::define ::cluster::service method ip     {} { return $ADDRESS }
::oo::define ::cluster::service method props  {} { return $PROPS   }
::oo::define ::cluster::service method tags   {} { return $TAGS    }
::oo::define ::cluster::service method local  {} { return $LOCAL   }
::oo::define ::cluster::service method hid    {} { return $SYSTEM_ID  }
::oo::define ::cluster::service method sid    {} { return $SERVICE_ID }

# How many seconds has it been since the last heartbeat was received from the service?
::oo::define ::cluster::service method last_seen {} {
  return [expr { [clock seconds] - $LAST_HEARTBEAT }]
}

::oo::define ::cluster::service method proto_props { protocol } {
  if { [dict exists $PROPS $protocol] } { return [dict get $PROPS $protocol] }
}