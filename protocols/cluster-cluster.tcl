# This example shows the (t) (TCP) protocol handler for the cluster-comm package.
# A protocol is a class which provides a translation of a protocol so that we can
# communicate successfully with it with cluster-comm. 
#
# A protocol must generally define both a SERVER and a CLIENT handler.  For our 
# server, we expect to listen to connections from clients and pass them to our
# cluster so it can be properly handled.

package require udp

if { [info commands ::cluster::protocol::c] eq {} } {
  ::oo::class create ::cluster::protocol::c {}
}

::oo::define ::cluster::protocol::c {
  variable SOCKET PORT CLUSTER ID CONFIG
}

::oo::define ::cluster::protocol::c constructor { cluster id config } {
  set ID       $id
  set CONFIG   $config
  set CLUSTER  $cluster
  my CreateServer
}

::oo::define ::cluster::protocol::c destructor {
  chan close $SOCKET
}

# Join our UDP Cluster.  This is simply a multi-cast socket with "reuse" so that
# multiple clients on the same machine can communicate with us using the given
# cluster port.
::oo::define ::cluster::protocol::c method CreateServer {} {
  dict with CONFIG {}
  set SOCKET [udp_open $port reuse]
  chan configure $SOCKET  \
    -buffering   full     \
    -blocking    0        \
    -translation binary   \
    -mcastadd    $address \
    -remote      [list $address $port] \
    -ttl         $remote
  chan event $SOCKET readable [namespace code [list my Receive]]
} 

# When we receive data from the cluster, we handle it the same way as-if we 
# receive from any other protocol.  Since we can call [chan configure $chan -peer]
# we can still apply our Security Policies against it if required.  
::oo::define ::cluster::protocol::c method Receive {} {
  set data [read $SOCKET]
  $CLUSTER receive c $SOCKET $data
}

# This protocol has no props that need to be shared.
::oo::define ::cluster::protocol::c method props {} {}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
::oo::define ::cluster::protocol::c method send { op data service } {
  try {
    set payload [list $op [$CLUSTER uuid]]
    if { $data ne {} } { lappend payload $data }
    puts $SOCKET $payload
    chan flush $SOCKET
  } on error {result options} {
    ::onError $result $options "While Sending to Cluster Protocol: $op $data"
    return 0
  }
  return 1
}

::oo::define ::cluster::protocol::c method port {} { return $PORT }

