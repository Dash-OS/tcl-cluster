# Broadcast to the cluster.  This is a shortcut to send to the cluster protocol.
::oo::define ::cluster::cluster method broadcast { payload } {
  set proto [dict get $PROTOCOLS c] 
  try [my run_hook broadcast] on error {r} { return 0 }
  return [ $proto send [::cluster::packet::encode $payload] ]
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