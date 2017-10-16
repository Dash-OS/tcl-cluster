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
  variable SOCKET PORT CLUSTER ID STREAM
}

::oo::define ::cluster::protocol::t constructor { cluster id config } {
  set ID      $id
  set CLUSTER $cluster
  my CreateStream
  my CreateServer
}

::oo::define ::cluster::protocol::t method CreateStream {} {
  if {[info exists STREAM]} { return $STREAM }
  set STREAM [bpacket create stream [namespace current]::stream]
  $STREAM event [namespace code [list my ReceivePacket]]
  return $STREAM
}

::oo::define ::cluster::protocol::t destructor {
  catch { my CloseSocket $SOCKET }
  catch { $STREAM destroy }
}

## Expected Accessors which every protocol must have.
::oo::define ::cluster::protocol::t method proto {} { return t }

# The props that are required to successfully negotiate with the protocol.
# These are sent to the members of the cluster so that they can understand
# what steps should be taken to establish a communications channel when using
# this protocol.
::oo::define ::cluster::protocol::t method props {} {
  return [dict create \
    port $PORT
  ]
}

# A service descriptor is used to define a protocols properties and to aid in
# securing the protocol and understanding how we need to negotiate with it.
# Every descriptor is expected to provide an "address" key.  Other than that it
# may define "port", "local" (is it a local-only protocol), etc.  They are available
# to hooks at various points.
::oo::define ::cluster::protocol::t method descriptor { chanID } {
  lassign [chan configure $chanID -peername] address hostname port
  return [ dict create \
    address  $address  \
    hostname $hostname \
    port     $port
  ]
}

# On each heartbeat, each of our protocol handlers receives a heartbeat call.
# This allows the service to run any commands that it needs to insure that it
# is still operating as expected.
::oo::define ::cluster::protocol::t method event { event args } {
  switch -- $event {
    heartbeat {
      # On each heartbeat, each of our protocol handlers receives a heartbeat call.
      # This allows the service to run any commands that it needs to insure that it
      # is still operating as expected.
    }
    refresh {
      my CreateServer
      $CLUSTER heartbeat
    }
    service_lost {
      # When a service is lost, each protocol is informed in case it needs to do cleanup
      lassign $args service
    }
  }
}


# When we want to send data to this protocol we will call this with the
# service that we are wanting to send the payload to. We should return
# 1 or 0 to indicate success of failure.
#
# $service is not strictly required by all protocols so it is possible that
# it will not be included.  Should this protocol require a reference to the
# service then it should simply throw an error.
::oo::define ::cluster::protocol::t method send { packet {service {}} } {
  try {
    # Get the props and data required from the service
    if { $service eq {} } {
      throw error "No Service Provided to TCP Protocol"
    }
    # First check if we have an open socket and see if we can use that. If
    # we can, continue - otherwise open a new connection to the client.
    set sock [$service socket t]
    if {$sock ne {}} {
      try {
        if {[chan eof $sock]} {
          catch { chan close $sock }
          set sock {}
        } else {
          puts -nonewline $sock $packet
        }
      } on error {result options} {
        my CloseSocket $sock $service
        set sock {}
      }
    }
    if { $sock eq {} } {
      set sock [my OpenSocket $service]
      puts -nonewline $sock $packet
    }
    if {$sock ne {}} {
      chan flush $sock
    }
    return 1
  } on error {r} {
    # Pass 0 to caller
  }
  return 0
}

## Below are methods that are either specific to the protocol or that are
## not required by the cluster.

::oo::define ::cluster::protocol::t method CreateServer {} {
  if { [info exists SOCKET] } {
    catch {
      my CloseSocket $SOCKET
    }
  }
  set SOCKET [socket -server [namespace code [list my Connect]] 0]
  set PORT   [lindex [chan configure $SOCKET -sockname] end]
  $CLUSTER event channel server [my proto] $SOCKET
}

::oo::define ::cluster::protocol::t method Connect { chanID address port {service {}} } {
  chan configure $chanID \
    -blocking    0 \
    -translation binary \
    -buffering   full

  chan event $chanID readable [namespace code [list my Receive $chanID]]

  $CLUSTER event channel open [my proto] $chanID $service
}

::oo::define ::cluster::protocol::t method Receive chanID {
  try {
    if {[chan eof $chanID]} {
      my CloseSocket $chanID
    } else {
      $STREAM append [read $chanID] $chanID
    }
  } on error {result options} {
    catch {::onError $result $options "Cluster - TCP Receive Error" $chanID}
  }
}

# called by our bpacket stream when it receives a full packet
::oo::define ::cluster::protocol::t method ReceivePacket {packet chanID} {
  $CLUSTER receive [my proto] $chanID $packet
}

::oo::define ::cluster::protocol::t method CloseSocket { chanID {service {}} } {
  if {$chanID in [chan names]} {
    chan close $chanID
  }
  $CLUSTER event channel close [my proto] $chanID $service
}

::oo::define ::cluster::protocol::t method OpenSocket { service } {
  set props [$service proto_props t]

  if { $props eq {} } {
    throw error "Services TCP Protocol Props are Unknown"
  } elseif { ! [dict exists $props port] } {
    throw error "Unknown TCP Port for $service"
  }

  set address [$service ip]
  set port    [dict get $props port]

  # TODO: Change this to use -async
  set sock [socket $address $port]

  my Connect $sock $address $port $service

  return $sock
}

# Called by our service when we have finished parsing the received data. It includes
# information as-to how the completed data should be parsed.
# Cluster ignores any close requests due to no keep alive.
::oo::define ::cluster::protocol::t method done { service chanID keepalive {response {}} } {
  if { [string is false $keepalive] } {
    my CloseSocket $chanID $service
  }
}
