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
  set ID      $id
  set CONFIG  $config
  set CLUSTER $cluster
  my CreateServer
}

::oo::define ::cluster::protocol::c destructor {
  catch { chan close $SOCKET }
}

::oo::define ::cluster::protocol::c method proto {} { return c }

# The props that are required to successfully negotiate with the protocol.
# These are sent to the members of the cluster so that they can understand 
# what steps should be taken to establish a communications channel when using
# this protocol.
::oo::define ::cluster::protocol::c method props {} {}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
::oo::define ::cluster::protocol::c method send { packet {service {}} } {
  try {
    if { [string bytelength $packet] > 0 } {
      puts -nonewline $SOCKET $packet
      chan flush $SOCKET
    }
  } on error {result options} {
    catch { my CreateServer }
    try {
      puts -nonewline $SOCKET $packet
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
::oo::define ::cluster::protocol::c method done { service chanID keepalive {response {}} } {}

# A service descriptor is used to define a protocols properties and to aid in 
# securing the protocol and understanding how we need to negotiate with it.  
# Every descriptor is expected to provide an "address" key.  Other than that it 
# may define "port", "local" (is it a local-only protocol), etc.  They are available
# to hooks at various points.
::oo::define ::cluster::protocol::c method descriptor { chanID } {
  return [ dict create \
    address [lindex [chan configure $chanID -peer] 0]  \
    port    $PORT
  ]
}

# On each heartbeat, each of our protocol handlers receives a heartbeat call.
# This allows the service to run any commands that it needs to insure that it
# is still operating as expected.
::oo::define ::cluster::protocol::c method event { event args } {
  switch -- $event {
    refresh {

    }
    heartbeat {
      # On each heartbeat, each of our protocol handlers receives a heartbeat call.
      # This allows the service to run any commands that it needs to insure that it
      # is still operating as expected.
      
    }
    service_lost {
      # When a service is lost, each protocol is informed in case it needs to do cleanup
      lassign $args service
    }
  }
}


## Below are methods that are either specific to the protocol or that are 
## not required by the cluster.


# Join our UDP Cluster.  This is simply a multi-cast socket with "reuse" so that
# multiple clients on the same machine can communicate with us using the given
# cluster port.
::oo::define ::cluster::protocol::c method CreateServer {} {
  dict with CONFIG {}
  if { [info exists SOCKET] } {
    catch { chan close $SOCKET }
  }
  set SOCKET [udp_open $port reuse]
  set PORT   $port
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
  if { [chan eof $SOCKET] } {
    catch { chan close $SOCKET }
    after 0 [namespace code [list my CreateServer]]
    return
  }
  set packet [read $SOCKET]
  $CLUSTER receive [my proto] $SOCKET $packet
}
