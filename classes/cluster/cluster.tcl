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



