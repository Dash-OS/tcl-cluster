::oo::define ::cluster::cluster {
  variable ID NS UUID CONFIG AFTER_ID PROTOCOLS HOOKS EVENTS
}

::oo::define ::cluster::cluster constructor { id config } {
  # Strip any periods (.) from the name as they are not allowed.  We do this
  # instead of producing an error.
  dict set config name [string map { {.} {} } [dict get $config name]]
  set ID       $id
  set CONFIG   $config
  set AFTER_ID {}
  set HOOKS    [dict create]
  set EVENTS   [dict create]
  set NS       ::cluster::clusters::${ID}
  namespace eval $NS {}
  namespace eval ${NS}::services {}
  my BuildUUID
  my BuildProtocols
  my heartbeat 1
  my discover
}

# We need to destroy our various objects in the appropriate order so they have
# access to the pieces they may need to clean themselves up.
::oo::define ::cluster::cluster destructor {
  if { [namespace exists ${NS}::services] } {
    # Delete the namespace holding all of our services attached to this cluster.
    namespace delete ${NS}::services
  }
  if { [namespace exists ${NS}::protocols] } {
    # Delete the namespace holding all of our protocols
    namespace delete ${NS}::protocols
  }
  # Delete our entire namespace
  namespace delete ${NS}
}

# Use append instead of string cat for compatibility with older versions of tcl
# A UUID takes the form of $hwaddr@${name}.[join $protocols .]
# 00:1F:C5:85:65:25@dash-access.c.t
::oo::define ::cluster::cluster method BuildUUID {} {
  set UUID {}
  append UUID [cluster hwaddr] @ [join [list \
    [dict get $CONFIG name] {*}[dict get $CONFIG protocols]
  ] .]
  puts "UUID IS: $UUID"
}

# Build any protocols that our cluster supports.  These will be used to build
# the communication channels with the clients.  We may have a mix of protocols
# supported by a cluster as well. We expect a cluster and tcp protocol in the
# minimum but other protocols may be supported.  We would need to run a service
# query to discover how to communicate with them.
#
# We expect any supported protocols to be classes defined in the ::cluster::protocol::$protocol
# command space where the protocol will receive [self] $ID $config arguments and should 
# provide capabilities for both sending and receiving using the protocol.
::oo::define ::cluster::cluster method BuildProtocols {} {
  namespace eval ${NS}::protocols {}
  foreach protocol [dict get $CONFIG protocols] {
    if { [info commands ::cluster::protocol::$protocol] ne {} } {
      dict set PROTOCOLS $protocol \
        [::cluster::protocol::$protocol create \
          ${NS}::protocols::$protocol [self] $ID $CONFIG
        ]
    } else {
      # If we do not know the given protocol, raise an error
      throw error "Unknown Cluster Protocol Requested: $protocol"
    }
  }
  #
}

# We send a heartbeat to the cluster at the given interval.  Any listening services
# will reset their timers for our service as they know we still exist.s
::oo::define ::cluster::cluster method heartbeat { {includeprops 0} } {
  after cancel $AFTER_ID
  set AFTER_ID [ after [dict get $CONFIG heartbeat] [namespace code [list my heartbeat]] ]
  if { $includeprops } {
    my send c ! [my ProtoProps]
  } else { my send c ! }
}

# Called by any of our supported protocols to parse / handle a received payload
# from a remote/local client.  We will check to make sure the given service passes
# our Security Policies and pass the payload through to our handlers if it does.
#
# Payloads will follow the protocol:
#   $op$ruid $UUID $payload
#
# Payload Parameters:
#   op      -   Our op code routes the payload to appropriate handler.
#   ruid    -   A RUID identifies a request so we can pass it through to the
#               response allowing asynchronous resolution. If any service responds
#               to a received payload, the service will expect this value included
#               as the ruid.
#   uuid    -   UUID of the sender $hwaddr@$port - we further identify the
#               sender by reading the meta from the service directly.
#   payload -   Any payload that was included with the request.
#
::oo::define ::cluster::cluster method receive {proto chan data} {
  set data [string trim $data]
  if { $data eq {} } { return }
  lassign $data opdata uuid payload
  # We ignore messages from ourselves
  if { $uuid eq $UUID } { return }
  # What are we receiving?
  set op   [string index $opdata 0]
  # What is the request unique id?
  set ruid [string range $opdata 1 end]
  # Who are we receiving it from? [list ip port]
  set peer [chan configure $chan -peer]
  # What is the service?  Does it pass Security Policy?
  set service [my service $uuid $peer]
  
  # Evaluate the cluster receive hooks
  try [my Hook protocol $proto receive] on error {r} { return }
  try [my Hook receive] on error {r} { return }
  
  puts "Receive Communication from $uuid :"
  puts "Protocol: $proto | OP: $op | RUID: $ruid | Peer: $peer | Service: $service"
  
  # If we have a valid service then we will parse the received data.
  # A valid service will have been validated and accepted based on the
  # initializer rules (local/remote, ip filters/port filters, etc)
  if { $service ne {} } {
    # ! - Heartbeat
    # ? - Discovery Request
    # * - Other Handlers are handled by the handlers
    switch -- $op {
        ! { 
          # When we receive a heartbeat we will simply reset the ttl for the 
          # service by sending it a heartbeat directly.
          $service heartbeat $payload
      } ? { 
          # When we receive a discovery request, we send our response
          # to the service directly based on the protocol qos it provides.
          #
          # If a discovery request contains a payload, we expect it to be a 
          # list of services that it is currently aware of.  If we are within
          # the given payload, we will not send it a response.  
          #
          # A response to a discovery request includes extra information about 
          # ourselves such as protocol properties.
          if { $payload ne {} && $UUID in $payload } { return }
          $service send ! $ruid [my ProtoProps]
      } default {
          # If we don't define a handler above, we will only continue
          # further if the given $op has a defined handler.
          try [my Hook op $op receive] on error {r} { return }
      }
    }
  }
}

# Gather the public properties of each protocol that we support.
::oo::define ::cluster::cluster method ProtoProps {} {
  set protoProps [dict create]
  dict for { protocol ref } $PROTOCOLS {
    set props [$ref props]
    if { $props ne {} } { dict set protoProps $protocol $props }
  }
  return $protoProps
}

# Whenever we receive data, we will check to see if the service already exists
# within our cache.  If it does, we will return a reference to the service.  If 
# it doesn't, we will create it then return its reference. 
#
# If a service should not be allowed to communicate with us, we will return an 
# empty string at which point the command should cease to parse the received
# payload immediately.
::oo::define ::cluster::cluster method service { uuid peer } {

  # Parse the UUID and split it into its parts so that we can properly
  # find our service object.
  lassign [::cluster::split_uuid $uuid] hwaddr name protocols
  set service ${NS}::services::${hwaddr}@${name}
  
  # The peer descriptior which describes the peer that we are receiving a
  # payload from.  This includes a mix of $uuid data as well as the data 
  # we parsed from the socket itself.
  set descriptor [dict create \
    uuid      $uuid   \
    peer      $peer   \
    name      $name   \
    hwaddr    $hwaddr \
    protocols $protocols
  ]
  
  # Call our service eval hook
  try [my Hook service eval] on error {r} { return }
  
  if { [info commands $service] ne {} } {
    # If our service already exists, we will validate it against the
    # received data to determine if we want to allow communication
    # with the service.  If we validate, then we will return the 
    # reference to the service to our handler.
    try [my Hook service validate] on error {r} { return }
    if { [$service validate $descriptor] } { return $service }
  } else {
    # If we have never seen this service, we will create it.  We will check
    # it against our security policies and retain it if it is a service we 
    # are allowed to communicate with.  Otherwise it will be destroyed.
    # Call our op receive hook
    try [my Hook service found] on error {r} { return }
    try {
      return [::cluster::service create $service [self] $descriptor]
    } on error {r} {
      puts "Service Creation Error: $r"
      # Do nothing on creation error
    }
  }
  return
  
}

::oo::define ::cluster::cluster method service_lost { service } {
  try [my Hook servoce lost] on error {r} { return }
}

# Currently we just save the hooks without validating them as a supported hook.
# protocol hooks are $protocol send/receive
# global hooks are send/receive
::oo::define ::cluster::cluster method hook args {
  set body [lindex $args end]
  set path [lrange $args 0 end-1]
  dict set HOOKS {*}$path $body
}

# When we want to retrieve the body for a given hook, we call this method with
# the desired hook key.  We will either return {} or the given hooks body to be
# evaluated.
::oo::define ::cluster::cluster method Hook args {
  if { $HOOKS eq {} } { return }
  tailcall ::cluster::ifhook $HOOKS {*}$args
}

# When we want to call a given event, this will be called with the event that has
# occurred. If a callback has been registered on the event, we call the lambda.
::oo::define ::cluster::cluster method Event args {
  if { $EVENT eq {} } { return }
  tailcall ::cluster::ifhook $EVENTS {*}$args
}


# Get our scripts UUID to send in payloads
::oo::define ::cluster::cluster method uuid {} { return $UUID }

# Retrieve how long a service should be cached by the protocol.  If we do not
# hear from a given service for longer than the $ttl value, the service will be 
# removed from our cache.
::oo::define ::cluster::cluster method ttl  {} { return [dict get $CONFIG ttl] }

# A list of all the currently known services
::oo::define ::cluster::cluster method services {} {
  return [info commands ${NS}::services::*]
}

::oo::define ::cluster::cluster method names {} {
  return [lmap e [my services] { $e name }]  
}

::oo::define ::cluster::cluster method ips {} {
  set ips [list]
  foreach service [my services] {
    set ip [$service ip]
    if { $ip ni $ips } { lappend ips $ip }
  }
  return $ips
}

::oo::define ::cluster::cluster method macs {} {
  set macs [list]
  foreach service [my services] {
    set mac [$service hwaddr]
    if { $mac ni $macs } { lappend macs $mac }
  }
  return $macs
}

# Get a reference to a service by the name.  We should eventually start using
# an indexed dict to get these values rather than querying each service looking
# for it.
#
# We resolve with the services "name" "ip" "uuid" "protocols" 
#
# If $all is true, return all matching services.
::oo::define ::cluster::cluster method resolve { name {all 0} } {
  set services [list]
  foreach service [my services] {
    if { $name in [$service resolver] } { 
      lappend services $service
      if { ! $all } { break }
    }
  }
  return $services
}

# When we want to send to a specific protocol, we call this to retrieve the
# appropriate protocol reference and forward the request.  If the protocol attempted
# is not supported by our cluster, we will immediately return "false" (0) to the 
# caller.
::oo::define ::cluster::cluster method send { proto op {data {}} {service {}} } {
  if { [dict exists $PROTOCOLS $proto] } {
    try [my Hook op [string index $op 0] send] on error {r} { return 0 }
    try [my Hook protocol $proto send] on error {r} { return 0 }
    try [my Hook send] on error {r} { return 0 }
    # Send to the protocol
    tailcall [dict get $PROTOCOLS $proto] send $op $data $service
  } else { return 0 }
}

::oo::define ::cluster::cluster method broadcast { op {data {}} } {
  return [ my send c $op $data ]
}

# Send to one or more services 
::oo::define ::cluster::cluster method sendto { services op  {data {}} {ruid {}} } {
  set sent [list]
  foreach service $services {
    set resolved [my resolve $service 1]
    foreach rservice $resolved {
      if { $rservice ni $sent } {
        try { $rservice send $op $ruid $data } on error {result} {
          puts "Failed to Send to Service: $rservice - $result"
        }
        lappend sent $rservice
      }
    }
  }
}

# Send a discovery probe to the cluster.  Each service will send its response
# based on the best protocol it can find. 
::oo::define ::cluster::cluster method discover {} {
  my send c ?
}