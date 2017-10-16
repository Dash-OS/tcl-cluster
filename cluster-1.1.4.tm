namespace eval ::cluster {
  namespace ensemble create
  namespace export {[a-z]*}

  namespace eval cluster  {}
  namespace eval protocol {}
}

variable ::cluster::script_dir [file dirname \
  [file normalize [info script]]
]

if 0 {
  | When tcl-modules is already added, we do not need to add
  | the tcl-modules to our path.  This is included so that
  | those that use the repo directly rather than as a tcl-module
  | can still require and use the package with the included
  | tcl-modules folder in the repo.
}
if {$::cluster::script_dir ni [::tcl::tm::path list]} {
  catch { ::tcl::tm::path add [file join $::cluster::script_dir tcl-modules] }
}

package require bpacket
package require unix 1.1 ; # Need this for initial OSX Support
package require shortid

# Source our general utilities first since they
# are needed for the evaluation below.
source [file join \
  $::cluster::script_dir cluster utils general.tcl
]

if 0 {
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

if 0 {
  @ ::cluster::cluster @ {class}
    | $::cluster::cluster instances are created for each cluster that
    | is joined.
}
::oo::class create ::cluster::cluster {}

if 0 {
  @ ::cluster::services @ {class}
    | Each discovered service (member of a cluster) will be
    | an instance of our $::cluster::services class.
}
::oo::class create ::cluster::service {}

if 0 {
  @ $::cluster::addresses {?list<IP>?}
   | Used to store our systems local IP Addresses.  Primed by
   | calling [::cluster::local_addresses]
}
variable ::cluster::addresses [list]

if 0 {
  @ $::cluster::i @ {entier}
    | A counter value used to generate unique session values
}
variable ::cluster::i 0

if 0 {
  @ $::cluster::DEFAULT_CONFIG @ {ClusterCommConfiguration}
}
variable ::cluster::DEFAULT_CONFIG [dict create \
  address     230.230.230.230 \
  port        23000 \
  ttl         600 \
  heartbeat   [::cluster::rand 110000 140000] \
  protocols   [list t c] \
  channels    [list] \
  remote      0 \
  tags        [list]
]

if 0 {
  @ ::cluster::source
    | Called when cluster is required.  It will source all the
    | necessary scripts in our sub-directories.  Once completed,
    | the proc is removed via [rename]
}
proc ::cluster::source {} {
  set classes_directory [file join $::cluster::script_dir cluster classes]
  foreach file [glob -directory $classes_directory *.tcl] {
    uplevel #0 [list source $file]
  }
  set protocol_directory [file join $::cluster::script_dir cluster protocols]
  foreach file [glob -directory $protocol_directory *.tcl] {
   uplevel #0 [list source $file]
  }
  set utils_directory [file join $::cluster::script_dir cluster utils]
  foreach file [glob -directory $utils_directory *.tcl] {
    if {[string match *general.tcl $file]} { continue }
    uplevel #0 [list source $file]
  }
  rename ::cluster::source {}
}

if 0 {
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
  } else {
    set protocols [dict get $config protocols]
  }
  dict for { k v } $args {
    set k  [string trimleft $k -]
    if { ! [dict exists $config $k] && $k ni $protocols } {
      throw CLUSTER_INVALID_ARGS "Invalid Cluster Config Key: ${k}, should be one of [dict keys $config]"
    }
    if { [string equal $k protocols] } {
      # cluster protocol is required, add if defined without it
      if { "c" ni $v } { lappend v c }
    }
    dict set config $k $v
  }
  set id [cluster id]
  return [::cluster::cluster create ::cluster::clusters::cluster_$id $id $config]
}

proc ::cluster::id {} {
  tailcall incr ::cluster::i
}

::cluster::source
