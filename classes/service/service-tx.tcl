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
