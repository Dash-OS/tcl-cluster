
# Each service that is discovered will have an object created which manages
# its lifecycle.
#
#
::oo::define ::cluster::service {
  variable CLUSTER UUID CHANNELS
  variable LAST_HEARTBEAT PROPS 
  variable PROTOCOLS FLAGS SERVICE_ID SYSTEM_ID
  variable SOCKETS ADDRESS TAGS LOCAL
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
  
  set ADDRESS    [dict get $descriptor address]
  if { [dict exists $descriptor local] } {
    set LOCAL [dict get $descriptor local] 
  } else { set LOCAL [$CLUSTER is_local $ADDRESS] }
  
  # Confirm that we can validate this service using our standard validate method.  This is called
  # directly by the cluster before parsing any payload after we have been created initially.
  if { ! [my validate $proto $chanID $payload $descriptor] } { throw error "Failed to Validate Discovered Service" }
}

::oo::define ::cluster::service destructor {
  catch { $CLUSTER service_lost [self] }
}

::oo::define ::cluster::service method heartbeat { {data {}} } {
  set LAST_HEARTBEAT [clock seconds]
  if { $data ne {} } {
    set PROPS [dict merge $PROPS $data] 
  }
}

::oo::define ::cluster::service method resolve { what {filter {}} } {
  if { $filter ne {} } { 
    switch -glob -- $what {
      *system*  - *hid  { if { $filter eq [my hid] } { return 1 } }
      *service* - *sid  { if { $filter eq [my sid] } { return 1 } }
      *ip - *address { if { $filter eq [my ip] } { return 1 } }
      *tag - *tags   { if { $filter in $TAGS   } { return 1 } }
    }
  } else {
    if { $what eq [my hid] || $what eq [my sid] } { return 1 }
    if { $what in $TAGS } { return 1 }
    if { $what eq [my ip] } { return 1 }
    if { $what eq "localhost" && [my local] } { return 1 } 
  }
  return 0
}

::oo::define ::cluster::service method query { args } {
  set query [lindex $args end]
  set ruid  [lindex $args end-1]
  set args  [lrange $args 0 end-2]
  if { [dict exists $args -timeout] } {
    
  }
  puts "Test Query"
  set payload [$CLUSTER query_payload $ruid $query]
  my send $payload
}

::oo::define ::cluster::service method send { payload {protocols {}} {allow_broadcast 1} } {
  if { $protocols eq {} } { set protocols $PROTOCOLS }
  # Encode the packet that we want to send to the cluster.
  set packet [::cluster::packet::encode $payload]
  set sent   {}
  set attempts [list]
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
    
    if { [$proto send $packet [self]] } { return $protocol } else { lappend attempts $protocol }
    
  }
  # If none of the attempted protocols were successful, we return an empty value
  # to the caller.
  puts "Failed to Send to Service: [self] [string bytelength $packet]"
  return
}

::oo::define ::cluster::service method receive { proto chanID payload descriptor } {
  #puts "[self] receives from $proto - $chanID"
  set data {}
  set PROTOCOLS [dict get $payload protocols]
  set protocol  [$proto proto]
  puts "Receiving via $protocol"
  dict with payload {}
  
  if { [info exists tags] } { set TAGS $tags }
  
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
      puts "SERVICE [self] DISCONNECTING"
    }
    1 {
      # Beacon
      puts "SERVICE HEARTBEAT"
      my heartbeat $data
    }
    2 {
      # Discovery
      puts "DISCOVERY REQUESTED BY SERVICE"
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
      # Request
    }
    4 {
      # Query
      puts "QUERY REQUESTED WITH RUID: $response"
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
  $proto done [self] $chanID $keepalive
}

::oo::define ::cluster::service method hook { context args } {
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

  if { [dict get $descriptor address] ne $ADDRESS } {
    set ADDRESS [dict get $descriptor address]
    if { [dict exists $descriptor local] } {
      set LOCAL [dict get $descriptor local] 
    } else {
      set LOCAL [$CLUSTER is_local $ADDRESS]
    }
  }
  
  set prevChan [my socket [$proto proto]]
  if { $prevChan ne $chanID } {
    my ChannelEvent open $proto $chanID
  }
  
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
      if { [dict exists $SOCKETS $protocol] && [dict get $SOCKETS $protcol] ne $chanID } {
        # A new channel is opening but we still have a reference to an older one?
        # We only allow one socket to each service per protocol - we call done on the previous
        $proto done [self] [dict get $SOCKETS $protocol] 0
      }
      dict set SOCKETS $protocol $chanID
    }
  }
}

::oo::define ::cluster::service method socket { proto } { 
  if { [dict exists $SOCKETS $proto] } {
    return [dict get $SOCKETS $proto] 
  }
}

::oo::define ::cluster::service method info {} {
  return [dict create \
    last_seen  $LAST_HEARTBEAT \
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
::oo::define ::cluster::service method proto_props { protocol } {
  if { [dict exists $PROPS $protocol] } { return [dict get $PROPS $protocol] }
}