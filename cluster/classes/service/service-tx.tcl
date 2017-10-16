::oo::define ::cluster::service method send { payload {protocols {}} {allow_broadcast 1} {ping_on_fail 1} {report_failures 1} } {
  try {
    if { $protocols eq {} } {
      set protocols $PROTOCOLS
    }
    # Encode the packet that we want to send to the cluster.
    if { ! [dict exists $payload filter] } {
      # When sending to a service, if a filter was not provided we will
      # add the service to the filter.  This is simply a security
      # mechanism to insure we are only sending this message to the given
      # service.
      dict set payload filter [my sid]
    }

    set packet [::cluster::packet::encode $payload]

    set sent   {}
    set attempts [list]
    #puts "Send to [self]"
    foreach protocol $protocols {
      if { $protocol in $attempts } {
        continue
      }
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
      } elseif { [string equal $protocol c] && ! $allow_broadcast } {
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
        #
        # In general a protocol will already implement a check like this, but we
        # want to run it so that we do not even attempt a transmission.  This way
        # if we try to send to a service that is not local we do not try to ping
        # it needlessly due to this failure.
        set descriptor [$proto descriptor]
        if { [dict exists $descriptor local] && [dict get $descriptor local] } {
          continue
        }
      }

      if {[$proto send $packet [self]]} {
        # If we successfully sent a packet and failed with other protocols, we
        # inform the given service of the failed protocols that we attempted
        # so that it can attempt to fix itself if possible.
        if { [llength $attempts] > 0 && $report_failures } {
          my ReportFailedAttempts $protocol $attempts $allow_broadcast
        }
        #puts "Success to $protocol"
        return $protocol
      } else {
        lappend attempts $protocol
      }
    }

    # We were unable to send to a service that was requested.  It is possible the service no longer
    # exists.  When this occurs we broadcast a public ping of the service to indicate to the other
    # members that it may no longer exist.  This way we can cleanup services before the TTL period
    # ends and reduce false resolutions during queries.
    if { [string is true -strict $ping_on_fail] && [llength $attempts] > 0 && [ my expected ] } {
      # We only schedule a ping in the case we havent heard from the service for awhile
      # or we are not already expecting a service to respond with a ping due to a previous
      # ping request from ourselves or another member.
      $CLUSTER schedule_service_ping [my sid]
    }

    # If none of the attempted protocols were successful, we return an empty value
    # to the caller.
    #::utils::flog "Failed to Send to Cluster Service | [self]"
    #puts "Failed to Send to Service: [self] [string bytelength $packet]"
    return
  } on error {result options} {
    catch { ::onError $result $options "While Sending to a Cluster Service" }
    throw error $result
  }
}

::oo::define ::cluster::service method ReportFailedAttempts { success_protocol failed_protocols allow_broadcast } {
  #puts "Report Failed : $failed_protocols "
  set payload [$CLUSTER failed_payload [dict create \
    protocols $failed_protocols
  ]]
  #puts "send $payload"
  #puts $success_protocol
  try {
    my send $payload $success_protocol $allow_broadcast 0 0
  } on error {r o} {
    puts stderr $r
  }
}
