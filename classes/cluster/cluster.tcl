::oo::define ::cluster::cluster {
  variable ID NS SYSTEM_ID SERVICE_ID CONFIG PROTOCOLS HOOKS TAGS AFTER_ID
  variable UPDATED_PROPS CHANNELS QID QUERIES COMM_CHANNELS
}

::oo::define ::cluster::cluster constructor { id config } {
  # Strip any periods (.) from the name as they are not allowed.  We do this
  # instead of producing an error.
  namespace path [list ::cluster {*}[namespace path]]
  set ID       $id
  set QUERIES  [dict create]
  set HOOKS    [dict create]
  set TAGS     [dict get $config tags]
  dict unset config tags
  set CONFIG   $config
  set NS       ::cluster::clusters::${ID}
  set AFTER_ID {}
  set CHANNELS [dict create]
  set COMM_CHANNELS [lsort -unique -real [list 0 1 2 {*}[dict get $config channels]]]
  namespace eval $NS {}
  namespace eval ${NS}::services {}
  namespace eval ${NS}::queries  {}
  set UPDATED_PROPS [list tags]
  my BuildSystemID
  my BuildProtocols
  my heartbeat
  my discover
}

# We need to destroy our various objects in the appropriate order so they have
# access to the pieces they may need to clean themselves up.
::oo::define ::cluster::cluster destructor {
  my variable SERVICES_TO_PING
  if { [info exists SERVICES_TO_PING] } {
    # Cancel our ping request
    if { [dict exists $SERVICES_TO_PING after_id] } {
      after cancel [dict get $SERVICES_TO_PING after_id] 
    }
  }
  after cancel $AFTER_ID
  if { [namespace exists ${NS}::services] } {
    # Delete the namespace holding all of our services attached to this cluster.
    namespace delete ${NS}::services
  }
  if { [namespace exists ${NS}::protocols] } {
    # Delete the namespace holding all of our protocols
    namespace delete ${NS}::protocols
  }
  if { [namespace exists ${NS}::queries] } {
    # Delete the namespace holding our query objects
    namespace delete ${NS}::queries 
  }
  # Delete our entire namespace
  namespace delete ${NS}
}

# Provide the desired system id which we will include with any packets that
# we encode.
::oo::define ::cluster::cluster method BuildSystemID {} {
  set SYSTEM_ID  [::cluster::hwaddr]
  set SERVICE_ID [shortid]
}

# Build any protocols that our cluster supports.  These will be used to build
# the communication channels with the clients.  We may have a mix of protocols
# supported by a cluster as well.
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
}

::oo::define ::cluster::cluster method CheckServices {} {
  # Check through each of our services to see if they have expired
  foreach service [my services] {
    try {
      set info [$service info]
      if { [dict exists $info last_seen] } { 
        set lastSeen [dict get $info last_seen]
        if { $lastSeen > [dict get $CONFIG ttl] } { $service destroy }
      } else { $service destroy }
    } on error {result options} {
      ~ "Service Check Error: $result"
      catch { $service destroy }
    }
  }
}

::oo::define ::cluster::cluster method CheckProtocols {} {
  dict for { protocol proto } $PROTOCOLS { catch { $proto heartbeat } }
}

# Gather the public properties of each protocol that we support.
::oo::define ::cluster::cluster method ProtoProps { {pdict {}} } {
  dict for { protocol ref } $PROTOCOLS {
    set props [$ref props]
    if { $props ne {} } { dict set pdict $protocol $props }
  }
  return $pdict
}

# Called by any of our supported protocols to parse / handle a received payload
# from a remote/local client.  We will check to make sure the given service passes
# our Security Policies and pass the payload through to our handlers if it does.
::oo::define ::cluster::cluster method receive { proto chanID packet } {
  try {
    # Trim then check to make sure the data is not empty. If it is, cancel evaluation.
    if { [string trim $packet] eq {} } { return }
    
    # Get information about the requester from the protocol
    set descriptor [ $proto descriptor $chanID ]
    
    if { [dict get $CONFIG remote] == 0 } {
      # When we have defined that we only wish to work with local scripts, we will 
      # check and immediately ignore any data received from outside the localhost
      if { ! [dict exists $descriptor local] } {
        if { ! [my is_local [dict get $descriptor address]] } { 
          return 
        } else { dict set descriptor local 1 }
      } else {
        if { ! [dict get $descriptor local] } { return }
      }
    }
    
    # Attempt to decode the received packet.  
    # An empty payload will be returned if we fail to decode the packet for any reason.
    set payload [::cluster::packet::decode $packet [self]]
    if { $payload eq {} || ! [dict exists $payload sid] || [dict get $payload sid] eq $SERVICE_ID } {
      # Ignore empty payloads or payloads that we receive from ourselves.
      return
    }
    # Are we currently listening to the channel that the communication was
    # received on?
    if { [dict get $payload channel] ni $COMM_CHANNELS } {
      puts "Not In Received Channel"
      return
    }
    # Called before anything is done with the received payload but after it is
    # decoded. $payload may be modified if necessary before it is further evaluated.
    try [my run_hook evaluate receive] on error {r} { return }
    
    try [my run_hook channel receive [dict get $payload channel]] on error {r} { return }
    
    #lassign $payload type rchan op ruid system_id service_id protocols flags data
    
    # Provide the data to the matching service to handle and parse.  Create the
    # service if it does not exist.  
    # - If we receive an empty value in return, the received data has been rejected.
    set service [my service $proto $chanID $payload $descriptor]
    if { $service eq {} } { return }
    
    set protocol [$proto proto]
    if { $protocol ne "c" } {
      my event channel receive $protocol $chanID $service
    }
    
    $service receive $proto $chanID $payload $descriptor
    
  } on error {result options} {
    ::onError $result $options "While Parsing a Received Cluster Packet"
  }
}

# A filter is a list of services which should parse / receive the given payload.
# It is used as an insecure way of routing broadcasted data to specific clients 
# When we have not yet created a channel.  For example, it can be useful to request
# a group of clients to join a specific channel.
::oo::define ::cluster::cluster method check_filter { filter } {
  #puts "Checking Filter: $filter"
  if { $SERVICE_ID in $filter } { return 1 }
  if { $SYSTEM_ID in $filter } { return 1 }
  foreach tag $TAGS { if { $tag in $filter } { return 1 } }
  return 0
}

# Whenever we receive data, we will check to see if the service already exists
# within our cache.  If it does, we will return a reference to the service.  If 
# it doesn't, we will create it then return its reference. 
#
# If a service should not be allowed to communicate with us, we will return an 
# empty string at which point the command should cease to parse the received
# payload immediately.
::oo::define ::cluster::cluster method service { proto chanID payload descriptor } {
  set system_id  [dict get $payload hid]
  set service_id [dict get $payload sid]
  
  # Added Security - if the system id does not match, we dont parse it when only
  # accepting local.
  if { [dict get $CONFIG remote] == 0 && $system_id ne $SYSTEM_ID } { return }
  
  set uuid ${service_id}@${system_id}
  
  set service ${NS}::services::$uuid
  
  set serviceExists [expr { [info commands $service] ne {} }]
  
  # Call our service eval hook
  try [my run_hook evaluate service] on error {r} { return }
  
  if { [string is true $serviceExists] } {
    # If our service already exists, we will validate it against the
    # received data to determine if we want to allow communication
    # with the service.  If we validate, then we will return the 
    # reference to the service to our handler.
    try [my run_hook service validate] on error {r} { return }
    
    if { [$service validate $proto $chanID $payload $descriptor] } { return $service }
  } else {
    # If we have never seen this service, we will create it.  We will check
    # it against our security policies and retain it if it is a service we 
    # are allowed to communicate with.  Otherwise it will be destroyed.
    try {
      set service [::cluster::service create $service [self] $proto $chanID $payload $descriptor]
      return $service
    } on error {r} {
      ~ "Service Creation Error: $r"
      # Do nothing on creation error
    }
  }
  return
}

# $cluster send \
#   -resolve   [list] \
#   -services  [list] \
#   -filter    [list] \
#   -protocols [list] \
#   -channel   0 \
#   -ruid      {} \
  