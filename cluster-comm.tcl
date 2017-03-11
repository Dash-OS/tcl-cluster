namespace eval ::cluster {
  namespace eval cluster  {}
  namespace eval protocol {}
  namespace ensemble create
  namespace export {[a-z]*}
  # Our cached addresses will be stored here
  variable addresses [list]
  # A coounter for ID's and such
  variable i 0
  
  proc rand {min max} { expr { int( rand() * ( $max - $min + 1 ) + $min )} }
  # Our default configuration which also enforces the allowed arguments
  variable default_config [dict create \
    address     230.230.230.230 \
    port        23000 \
    ttl         600 \
    heartbeat   [::cluster::rand 110000 140000] \
    protocols   [list t c] \
    channels    [list] \
    remote      0 \
    tags        [list]
  ]
}

# temporary 
proc ::onError {r o args} {
  puts stderr "Error: $r $args"
  puts stderr $o
}
proc ::~ msg { puts stderr $msg }


# Build our initial classes.  We do this here so we can easily 
# replace code using definitions later.
::oo::class create ::cluster::cluster {}
::oo::class create ::cluster::service {}

proc ::cluster::source {} {
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
  set utils_directory [file join [file dirname [file normalize [info script]]] utils]
  foreach file [glob -directory $utils_directory *.tcl] {
    uplevel #0 [list source $file]
  }
  rename ::cluster::source {}
}

proc ::cluster::join args {
  variable i
  set config $::cluster::default_config
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
  set id [incr i]
  return [::cluster::cluster create ::cluster::clusters::cluster_$id $id $config]
}

proc ::cluster::query_id {} {
  return [incr ::cluster::i]
}

proc ::cluster::ifhook {hooks args} {
  if { [dict exists $hooks {*}$args] } {
    tailcall dict get $hooks {*}$args
  }
}

::cluster::source