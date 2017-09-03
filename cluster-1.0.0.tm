namespace eval ::cluster {
  namespace ensemble create
  namespace export {[a-z]*}

  namespace eval cluster  {}
  namespace eval protocol {}
}

# Source our general utilities first since they
# are needed for the evaluation below.
source [file join \
  [file dirname [file normalize [info script]]] utils general.tcl
]

% {
  @type ClusterCommunicationProtocol {mixed}
    | A ClusterCommunicationProtocol is any of the supported
    | protocols as provided within the [protocols] folder.
    | Generally these will be a single-character representation
    | as an example, "tcp" is "t" while "udp" is "u" and so-on.

  @type MulticastAddress {IP}
    | An IP Addresss within the range 224.0.0.0 to 239.255.255.255

  @type ClusterCommConfiguration {dict}
    | Our default configuration for the cluster.  This
    | dict also represents the configuration options
    | that are available when calling [::cluster::join]
    @prop address {MulticastAddress}
      The address that should be used as the multicast address
    @prop port /[0-65535]/
      The UDP multicast port that should be used
    @prop ttl {entier}
      How many seconds should a service live if it is not seen?
    @prop heartbeat {entier}
      At what interval should we send heartbeats to the cluster?
    @prop protocols {list<ClusterCommunicationProtocol>}
      A list providing the communication protocols that should be
      supported / advertised to our peers.  The list should be in
      order of desired priority.  Our peers will attempt to honor
      this priority when opening channels of communication with us.
    @prop channels {list<entier>}
      A list of communication channels that we should join.
    @prop remote {boolean}
      Should we listen outside of localhost? When set to false,
      the ttl of our multicasts will be set to 0 so that they
      do not leave the local system.
}

% {
  @ ::cluster::cluster @ {class}
    | $::cluster::cluster instances are created for each cluster that
    | is joined.
}
::oo::class create ::cluster::cluster {}

% {
  @ ::cluster::services @ {class}
    | Each discovered service (member of a cluster) will be
    | an instance of our $::cluster::services class.
}
::oo::class create ::cluster::service {}

% {
  @ $::cluster::addresses {?list<IP>?}
   | Used to store our systems local IP Addresses.  Primed by
   | calling [::cluster::local_addresses]
}
variable ::cluster::addresses [list]

% {
  @ $::cluster::i @ {entier}
    | A counter value used to generate unique session values
}
variable ::cluster::i 0

% {
  @ $::cluster::DEFAULT_CONFIG @ {ClusterCommConfiguration}
}
variable ::cluster::DEFAULT_CONFIG [dict create \
  address     230.230.230.230 \
  port        23000 \
  ttl         600 \
  heartbeat   [::cluster::rand 110000 140000] \
  protocols   [list t c] \
  channels    [list] \
  remote      false \
  tags        [list]
]

% {
  @ ::cluster::source
    | Called when cluster is required.  It will source all the
    | necessary scripts in our sub-directories.  Once completed,
    | the proc is removed via [rename]
}
proc ::cluster::source {} {
  set utils_directory [file join [file dirname [file normalize [info script]]] utils]
  foreach file [glob -directory $utils_directory *.tcl] {
    if {[string match *general.tcl $file]} { continue }
    uplevel #0 [list source $file]
  }
  set bpacket_directory [file join [file dirname [file normalize [info script]]] bpacket]
  foreach file [glob -directory $bpacket_directory *.tcl] {
    uplevel #0 [list source $file]
  }
  set classes_directory [file join [file dirname [file normalize [info script]]] classes]
  foreach file [glob -directory $classes_directory *.tcl] {
    uplevel #0 [list source $file]
  }
  set protocol_directory [file join [file dirname [file normalize [info script]]] protocols]
  foreach file [glob -directory $protocol_directory *.tcl] {
   uplevel #0 [list source $file]
  }

  rename ::cluster::source {}
}

% {
  @type ClusterCommConfiguration {dict}
    | Our default configuration for the cluster.  This
    | dict also represents the configuration options
    | that are available when calling [::cluster::join]
    @prop address {MulticastAddress}
      The address that should be used as the multicast address
    @prop port {/[0-65535]/}
      The UDP multicast port that should be used
    @prop ttl {entier}
      How many seconds should a service live if it is not seen?
    @prop heartbeat {entier}
      At what interval should we send heartbeats to the cluster?
    @prop protocols {list<ClusterCommunicationProtocol>}
      A list providing the communication protocols that should be
      supported / advertised to our peers.  The list should be in
      order of desired priority.  Our peers will attempt to honor
      this priority when opening channels of communication with us.
    @prop channels {list<entier>}
      A list of communication channels that we should join.
    @prop remote {boolean}
      Should we listen outside of localhost? When set to false,
      the ttl of our multicasts will be set to 0 so that they
      do not leave the local system.

  @ ::cluster::join
    | The core cluster command that is used as a factory to build
    | a new cluster instance.  A $::cluster::cluster object
    | is returned which can then be used to communicate with our
    | cluster.
  @arg args {dict<-key, value> from ClusterCommConfiguration}
    args are a key/value pairing with the configuration key being
    prefixed with a dash (-) and the value that should be used
    as its pair value. (-ttl 600 -port 10)
  @returns {object<::cluster::cluster>}
    When called, returns an object that can be used to communicate
    with the cluster.
}
proc ::cluster::join args {
  set config $::cluster::DEFAULT_CONFIG
  if { [dict exists $args -protocols] } {
    set protocols [dict get $args -protocols]
  } else { set protocols [dict get $config protocols] }
  dict for { k v } $args {
    set k [string trimleft $k -]
    if { ! [dict exists $config $k] && $k ni $protocols } {
      throw error "Invalid Cluster Config Key: ${k}, should be one of [dict keys $config]"
    }
    if { [string equal $k protocols] } {
      # cluster protocol is required, add if defined without it
      if { "c" ni $v } { lappend v c }
    }
    dict set config $k $v
  }
  set id [incr ::cluster::i]
  return [::cluster::cluster create ::cluster::clusters::cluster_$id $id $config]
}

::cluster::source
