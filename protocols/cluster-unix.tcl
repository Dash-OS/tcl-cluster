# This example shows the (u) (Unix Sockets) protocol handler for the cluster-comm package.
# A protocol is a class which provides a translation of a protocol so that we can
# communicate successfully with it with cluster-comm. 
#
# A protocol must generally define both a SERVER and a CLIENT handler.  For our 
# server, we expect to listen to connections from clients and pass them to our
# cluster so it can be properly handled.

package require unix_sockets

if { [info commands ::cluster::protocol::u] eq {} } {
  ::oo::class create ::cluster::protocol::u {}
}

::oo::define ::cluster::protocol::u {
  variable SOCKET SERVER_PATH CLUSTER ID
}

::oo::define ::cluster::protocol::u constructor { cluster id config } {
  set ID      $id
  set CLUSTER $cluster
  if { ! [dict exists $config u] } {
    throw error "u config must exist in cluster configuration"
  }
  if { ! [dict exists $config u path] } {
    throw error "Must define a path for our unix server within the u config" 
  }
  set SERVER_PATH [file normalize [file nativename [dict get $config u path]]]
  my CreateServer
}

::oo::define ::cluster::protocol::u destructor {
  catch { my CloseSocket $SOCKET }
}

## Expected Accessors which every protocol must have.
::oo::define ::cluster::protocol::u method proto {} { return u }

# The props that are required to successfully negotiate with the protocol.
# These are sent to the members of the cluster so that they can understand 
# what steps should be taken to establish a communications channel when using
# this protocol.
::oo::define ::cluster::protocol::u method props {} { 
  return [dict create \
    path $SERVER_PATH
  ]
}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
#
# $service is not strictly required by all protocols so it is possible that
# it will not be included.  Should this protocol require a reference to the
# service then it should simply throw an error.
::oo::define ::cluster::protocol::u method send { packet {service {}} } {
  try {
    # Get the props and data required from the service
    if { $service eq {} } { throw error "No Service Provided to UDP Protocol" }
    # Since this is a local protocol, we will only attempt to send if the
    # service is a local service
    if { ! [$service local] } { return 0 }
    # First check if we have an open socket and see if we can use that. If
    # we can, continue - otherwise open a new connection to the client.
    set sock [$service socket [my proto]]
    if { $sock ne {} } {
      try {
        puts -nonewline $sock $packet
      } on error {result options} {
        my CloseSocket $sock $service
        set sock {}
      }
    }
    if { $sock eq {} } {
      set sock [my OpenSocket $service]
      puts -nonewline $sock $packet
    }
    return 1
  } on error {r} {}
  return 0
}

# Called by our service when we have finished parsing the received data. It includes
# information as-to how the completed data should be parsed.
# Cluster ignores any close requests due to no keep alive.
::oo::define ::cluster::protocol::u method done { service chanID keepalive {response {}} } {
  if { [string is false $keepalive] } { my CloseSocket $chanID $service }
}

# A service descriptor is used to define a protocols properties and to aid in 
# securing the protocol and understanding how we need to negotiate with it.  
# Every descriptor is expected to provide an "address" key.  Other than that it 
# may define "port", "local" (is it a local-only protocol), etc.  They are available
# to hooks at various points.
::oo::define ::cluster::protocol::u method descriptor { chanID } {
  return [ dict create \
    local   1 \
    address $SERVER_PATH
  ]
}

# On each heartbeat, each of our protocol handlers receives a heartbeat call.
# This allows the service to run any commands that it needs to insure that it
# is still operating as expected.
::oo::define ::cluster::protocol::u method heartbeat {} {
  if { ! [file exists $SERVER_PATH] } { my CreateServer }
}

## Below are methods that are either specific to the protocol or that are 
## not required by the cluster.

::oo::define ::cluster::protocol::u method CreateServer { } {
  if { [file exists $SERVER_PATH] } { file delete -force $SERVER_PATH }
  if { [info exists SOCKET] } { catch { my CloseSocket $SOCKET } }
  set SOCKET [::unix_sockets::listen $SERVER_PATH [namespace code [list my Connect $SERVER_PATH {}]]]
} 

::oo::define ::cluster::protocol::u method Connect { path service chanID  } {
  chan configure $chanID -blocking 0 -translation binary -buffering none
  chan event $chanID readable [namespace code [list my Receive $chanID]]
  $CLUSTER event channel open [self] $chanID $service
}

::oo::define ::cluster::protocol::u method Receive { chanID } {
  try {
    if { [chan eof $chanID] } { 
      my CloseSocket $chanID 
      if { $chanID eq $SOCKET } { my CreateServer }
    } else {
      $CLUSTER receive [self] $chanID [read $chanID]
    }
  } on error {result options} {
    ::onError $result $options "Cluster - Unix Socket Receive Error"
  }
}

::oo::define ::cluster::protocol::u method CloseSocket { chanID {service {}} } {
  catch { chan close $chanID }
  $CLUSTER event channel close [self] $chanID $service
}

::oo::define ::cluster::protocol::u method OpenSocket { service } {
  set props [$service proto_props [my proto]]
  if { $props eq {} } { throw error "Services Unix Protocol Props are Unknown" }
  if { ! [dict exists $props path] } { throw error "Unknown Unix Socket Path for $service" }
  set path [dict get $props path]
  set sock [::unix_sockets::connect $path]
  my Connect $path $service $sock
  return $sock
}