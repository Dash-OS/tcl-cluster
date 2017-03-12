# This example shows the (t) (TCP) protocol handler for the cluster-comm package.
# A protocol is a class which provides a translation of a protocol so that we can
# communicate successfully with it with cluster-comm. 
#
# A protocol must generally define both a SERVER and a CLIENT handler.  For our 
# server, we expect to listen to connections from clients and pass them to our
# cluster so it can be properly handled.

package require udp

if { [info commands ::cluster::protocol::n] eq {} } {
  ::oo::class create ::cluster::protocol::n {}
}

::oo::define ::cluster::protocol::n {
  variable SOCKET PORT CLUSTER ID CONFIG MIDDLEMAN_IP MIDDLEMAN_PORT MIDDLEMAN_SECRET
}

::oo::define ::cluster::protocol::n constructor { cluster id config } {
  set ID $id
  set CONFIG  $config
  set CLUSTER $cluster
  if { ! [dict exists $config n] } {
    throw error "Cluster-NATT Requires the \"n\" configuration to operate" 
  }
  if { ! [dict exists $config n server] } {
    throw error "Cluster-NATT Needs \"server\" provided in it's configuration"
  }
  if { ! [dict exists $config n secret] } {
    throw error "Cluster-NATT Needs a \"secret\" to establish a connection"  
  }
  
  # We will use default port 19333 if the configuration does not provide a 2 element list.
  set server [dict get $config n server]
  if { [llength $server] == 1 } { 
    set MIDDLEMAN_IP   $server
    set MIDDLEMAN_PORT 19333 
  } else { lassign $server MIDDEMAN_IP MIDDLEMAN_PORT }
  
  # Our secret is used to establish a connection between NAT's using our middleman server
  set MIDDLEMAN_SECRET [dict get $config n secret]
  
  my ConnectToMiddleman
}

::oo::define ::cluster::protocol::n destructor {
  catch { chan close $SOCKET }
}

::oo::define ::cluster::protocol::n method proto {} { return c }

# The props that are required to successfully negotiate with the protocol.
# These are sent to the members of the cluster so that they can understand 
# what steps should be taken to establish a communications channel when using
# this protocol.
::oo::define ::cluster::protocol::n method props {} {}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
::oo::define ::cluster::protocol::n method send { packet {service {}} } {
  try {
    # First we need to encode the binary packet to base64 for transmission
    if { [string bytelength $packet] == 0 } { return 0 }
    set packet [my EncodePacket $MIDDLEMAN_SECRET $packet]
    puts $SOCKET $packet
    chan flush $SOCKET
  } on error {r} {
    catch { my ConnectToMiddleman }
    try {
      puts $SOCKET $packet
      chan flush $SOCKET
    } on error {result options} {
      ::onError $result $options "While Sending to the Cluster"
      return 0
    }
  }
  return 1
}

# Called by our service when we have finished parsing the received data. It includes
# information as-to how the completed data should be parsed.
# Cluster ignores any close requests due to no keep alive.
::oo::define ::cluster::protocol::n method done { service chanID keepalive {response {}} } {}

# A service descriptor is used to define a protocols properties and to aid in 
# securing the protocol and understanding how we need to negotiate with it.  
# Every descriptor is expected to provide an "address" key.  Other than that it 
# may define "port", "local" (is it a local-only protocol), etc.  They are available
# to hooks at various points.
::oo::define ::cluster::protocol::n method descriptor { chanID } {
  return [ dict create \
    address $MIDDLEMAN_IP  \
    port    $MIDDLEMAN_PORT
  ]
}

# On each heartbeat, each of our protocol handlers receives a heartbeat call.
# This allows the service to run any commands that it needs to insure that it
# is still operating as expected.
::oo::define ::cluster::protocol::n method heartbeat {} {

}


## Below are methods that are either specific to the protocol or that are 
## not required by the cluster.

::oo::define ::cluster::protocol::n method DecodePacket { encoded_packet } {
  lassign [ split [binary decode base64 $encode_packet] | ] secret packet
  if { $secret ne $MIDDLEMAN_SECRET } { 
    # This should not have happened, ignore the packet
    return
  }
  return $packet
}

::oo::define ::cluster::protocol::n method EncodePacket { secret packet } {
  return [binary encode base64 $secret|$packet]
}

# Join our UDP Cluster.  This is simply a multi-cast socket with "reuse" so that
# multiple clients on the same machine can communicate with us using the given
# cluster port.
::oo::define ::cluster::protocol::n method ConnectToMiddleman {} {
  set SOCKET [socket $MIDDLEMAN_IP $MIDDLEMAN_PORT]
  chan configure $SOCKET -buffering full -blocking 0 -encoding binary -translation auto
  chan event $SOCKET readable [namespace code [list my MiddlemanReceive]]
} 

# When we receive data from the cluster, we handle it the same way as-if we 
# receive from any other protocol.  Since we can call [chan configure $chan -peer]
# we can still apply our Security Policies against it if required.  
::oo::define ::cluster::protocol::n method MiddlemanReceive {} {
  if { [chan eof $SOCKET] } {
    catch { chan close $SOCKET }
    after 0 [namespace code [list my ConnectToMiddleman]]
    return
  }
  
  gets $SOCKET encoded_packet
  
  set packet [my DecodePacket $encoded_packet]
  
  $CLUSTER receive [self] $SOCKET $packet
}

::oo::define ::cluster::protocol::n method SwitchToDirectConnect {} {
  
}