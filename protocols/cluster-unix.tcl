package require unix_sockets
# This example shows the (t) (TCP) protocol handler for the cluster-comm package.
# A protocol is a class which provides a translation of a protocol so that we can
# communicate successfully with it with cluster-comm. 
#
# A protocol must generally define both a SERVER and a CLIENT handler.  For our 
# server, we expect to listen to connections from clients and pass them to our
# cluster so it can be properly handled.
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
::oo::define ::cluster::protocol::u method props {} { 
  return [dict create \
    path $SERVER_PATH
  ]
}

::oo::define ::cluster::protocol::u method CreateServer { } {
  puts "CREATE UNIX SERVER: $SERVER_PATH"
  if { [file exists $SERVER_PATH] } { file delete -force $SERVER_PATH }
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
    puts "TCP RECEIVE ERROR: $result"
  }
}

::oo::define ::cluster::protocol::u method CloseSocket { chanID {service {}} } {
  catch { chan close $chanID }
  $CLUSTER event channel close [self] $chanID $service
}

::oo::define ::cluster::protocol::u method OpenSocket { service } {
  set props [$service proto_props [my proto]]
  if { $props eq {} } { throw error "Services UDP Protocol Props are Unknown" }
  if { ! [dict exists $props path] } { throw error "Unknown UDP Path for $service" }
  set path [dict get $props path]
  set sock [::unix_sockets::connect $path]
  my Connect $path $service $sock
  return $sock
}

# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return 
# 1 or 0 to indicate success of failure.
::oo::define ::cluster::protocol::u method send { packet {service {}} } {
  try {
    # Get the props and data required from the service
    if { $service eq {} } { throw error "No Service Provided to UDP Protocol" }
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
  } on error {result options} {
    puts "Failed to Send to TCP Protocol: $result"
    puts $options
  }
  return 0
}

# Called by our service when we have finished parsing the received data. It includes
# information as-to how the completed data should be parsed.
# Cluster ignores any close requests due to no keep alive.
::oo::define ::cluster::protocol::u method done { service chanID keepalive {response {}} } {
  if { [string is false $keepalive] } { my CloseSocket $chanID $service }
}

::oo::define ::cluster::protocol::u method descriptor { chanID } {
  return [ dict create \
    local   1 \
    address $SERVER_PATH
  ]
}
