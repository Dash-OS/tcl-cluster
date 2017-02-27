# This example shows the (t) (TCP) protocol handler for the cluster-comm package.
# A protocol is a class which provides a translation of a protocol so that we can
# communicate successfully with it with cluster-comm. 
#
# A protocol must generally define both a SERVER and a CLIENT handler.  For our 
# server, we expect to listen to connections from clients and pass them to our
# cluster so it can be properly handled.
if { [info commands ::cluster::protocol::t] eq {} } {
  ::oo::class create ::cluster::protocol::t {}
}

::oo::define ::cluster::protocol::t {
  variable SOCKET PORT SESSIONS CLUSTER ID CHANNELS
}

::oo::define ::cluster::protocol::t constructor { cluster id config } {
  set ID $id
  set SESSIONS [list]
  set CHANNELS [dict create]
  set CLUSTER  $cluster
  my CreateServer
}

::oo::define ::cluster::protocol::t destructor {
  foreach session $SESSIONS {
    catch { $session @@close }
  }
}

::oo::define ::cluster::protocol::t method CreateServer {} {
  set SOCKET [socket -server [namespace code [list my Connect]] 0]
  set PORT   [lindex [chan configure $SOCKET -sockname] end]
} 

::oo::define ::cluster::protocol::t method Connect { chan address port } {
  chan configure $chan -blocking 0 -buffering line
  chan event $chan readable [namespace code [list my Receive $chan]]
}

::oo::define ::cluster::protocol::t method Receive { chan } {
  chan configure $chan -blocking 0 -buffering none -translation binary
  if { [chan eof $chan] } {
    chan close $chan
  } elseif { [chan gets $chan data] >= 0 } {
    $CLUSTER receive t $chan $data
  }
}

# When our public properties are requested, we respond with the tcp port
# we are listening on
::oo::define ::cluster::protocol::t method props {} {
  return [dict create \
    port $PORT
  ]
}

::oo::define ::cluster::protocol::t method OpenSocket { service } {
  set props [$service proto_props t]
  if { $props eq {} } { throw error "Services TCP Protocol Props are Unknown" }
  if { ! [dict exists $props port] } { throw error "Unknown TCP Port for $service" }
  set sock [socket [$service ip] [dict get $props port]]
  chan configure $sock -blocking 0 -buffering none
  return $sock
}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
::oo::define ::cluster::protocol::t method send { op data service } {
  try {
    # Get the props and data required from the service
    if { $service eq {} } { throw error "No Service Provided to TCP Protocol" }
    
    # Create the TCP Socket connection and send the payload.  Close the socket
    # immediately after sending the payload.
    set sock [my OpenSocket $service]
    
    set payload [list $op [$CLUSTER uuid]]
    if { $data ne {} } { lappend payload $data }
    
    # Send our payload to the socket
    puts $sock $payload
    chan close $sock
    return 1
  } on error {result options} {
    puts "Failed to Send to TCP Protocol: $result"
  }
  return 0
}

::oo::define ::cluster::protocol::t method port {} { return $PORT }