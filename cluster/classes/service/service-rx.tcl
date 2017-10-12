::oo::define ::cluster::service method heartbeat { {data {}} } {
  set LAST_HEARTBEAT [clock seconds]
  if { $data ne {} } {
    #puts "Service Props Received! $data"
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

::oo::define ::cluster::service method receive { proto chanID payload descriptor remaining } {
  set data {}
  set protocol [$proto proto]
  dict with payload {}
  # Did our partner provide us with a request uid?  If so, any reply will include the
  # ruid so it can identify the request.
  if { [info exists ruid] } {
    dict set response ruid $ruid
  } else {
    set response {}
  }

  # Did our partner request that we keep the channel alive?  If the property exists, we will
  # send it with any reply that may be sent.
  if { ! [info exists keepalive] } {
    set keepalive 0
  } else {
    dict set response keepalive $keepalive
  }
  #puts "[self] receives from $proto - $chanID - $type"
  #puts "RECEIVE $proto | $type"
  switch -- $type {
    0 {
      # Disconnect
      #~ "SERVICE [self] DISCONNECTING"
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
      } on error {r} {
        dict set response error $r
      }
      my send [$CLUSTER response_payload $response $channel] $protocol
    }
    5 {
      # Response
      # When a service provides us with a response to a query we will attempt to
      # call the query objects event method with a reference to our service.
      #
      # If the query has already timed out, nothing will happen.
      my heartbeat
      if { ! [info exists ruid] } {
        return
      }
      $CLUSTER query_response [self] $payload
      # Close the connection automatically after giving our response
      set keepalive 0
    }
    6 {
      # Event
      my hook $payload event
    }
    7 {
      # Flush Props / Replace with received data
      set PROPS $data
    }
    8 {
      # Failure
      # | When a cluster member has failed when attempting to work with this
      # | service, we receive a notification from that service to let us know
      # | that we need to attempt to provide a resolution.
      # puts "Failure Reported!"
      # puts $data
      if { [dict exists $data protocols] } {
        foreach protocol [dict get $data protocols] {
          set ref [$CLUSTER protocol $protocol]
          if { $ref ne {} } {
            catch {
              $ref event refresh
            }
          }
        }
      }
    }
  }
  if { [info exists NEW] } {
    unset NEW
    # After 1 second, call our service_discovered hook.  We provide a slight
    # delay because some services will send details about themselves after their
    # initial heartbeat.
    after 1000 [namespace code [list my hook $payload service discovered]]
  }
  # ~! "Proto Done" "Proto Done $chanID $keepalive" \
  #   -context "
  #     $descriptor

  #     $payload

  #   "
  if {$remaining == 0} {
    $proto done [self] $chanID $keepalive
  }

}
