namespace eval ::cluster {
  namespace ensemble create
  namespace export {[a-z]*}
  # Our cached addresses will be stored here
}

# Any dependencies based on the platform should be included here.
switch -- $::tcl_platform(platform) {
  unix { package require tuapi }
}

# these should be replaced in the future, they are for testing
proc ::onError {r o args} { 
  puts stderr "ERROR $result $args"
  puts stderr $o
}
proc ::~ msg { puts stderr $msg }

# Random number between....
proc ::cluster::rand {min max} { expr { int( rand() * ( $max - $min + 1 ) + $min )} }

variable ::cluster::i 0
variable ::cluster::addresses [list]
variable ::cluster::default_config [dict create \
  name        [pid] \
  address     230.230.230.230 \
  port        23000 \
  ttl         600 \
  heartbeat   [::cluster::rand 110000 140000] \
  protocols   [list t c] \
  remote      0 \
  tags        [list]
]

namespace eval ::cluster::clusters {}
namespace eval ::cluster::protocol {}
# Build our initial classes.  We do this here so we can easily 
# replace code using definitions later.
::oo::class create ::cluster::cluster {}
::oo::class create ::cluster::service {}

set bpacket_directory [file join [file dirname [file normalize [info script]]] bpacket]
foreach file [glob -directory $bpacket_directory *.tcl] {
  source $file
}
unset bpacket_directory

set classes_directory [file join [file dirname [file normalize [info script]]] classes]
foreach file [glob -directory $classes_directory *.tcl] {
  source $file
}
unset classes_directory

# Automatically source protocols in the protocols directory
set protocol_directory [file join [file dirname [file normalize [info script]]] protocols]
foreach file [glob -directory $protocol_directory *.tcl] {
 source $file 
}
unset protocol_directory

set utils_directory [file join [file dirname [file normalize [info script]]] utils]
foreach file [glob -directory $utils_directory *.tcl] {
  source $file
}
unset utils_directory

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

# Retrieve the hardware address for the platform.  Currently only handling unix
# platform.
proc ::cluster::hwaddr {} {
  switch $::tcl_platform(platform) {
    unix {
      dict for { iface params } [::tuapi::ifconfig] {
        if { ! [string equal $iface lo] && [dict exists $params hwaddr] } {
          return [string toupper [dict get $params hwaddr]]
        }
      }
    }
  }
}

# Retrieve the most likely lanip for the platform.  Not currently handling if multiple
# lan ip's are utilized, we return the first non-loopback address.
proc ::cluster::lanip {} {
  switch $::tcl_platform(platform) {
    unix {
      dict for { iface params } [::tuapi::ifconfig] {
        if { ! [string equal $iface lo] && [dict exists $params address] } {
          return [dict get $params address]
        }
      }
    }
  }
}

# Check a $peer value to see if it is from a local source or not.
proc ::cluster::islocal { descriptor } {
  if { [dict exists $descriptor address] } {
    set address [dict get $descriptor address] 
  } else { return 0 }
  if { $address eq "127.0.0.1" } { return 1 }
  switch $::tcl_platform(platform) {
    unix {
      dict for { iface params } [::tuapi::ifconfig] {
        if { [dict exists $params address] && [dict get $params address] eq $address } {
          return 1
        }
      }
    }
  }
  return 0
}

proc ::cluster::local_addresses {} {
  variable addresses
  if { $addresses ne {} } { return $addresses }
  set addresses [list 127.0.0.1]
  switch $::tcl_platform(platform) {
    unix {
      dict for { iface params } [::tuapi::ifconfig] {
        if { [dict exists $params address] } {
          set address [dict get $params address]
          if { $address ni $addresses } { lappend addresses $address }
        }
      }
    }
  }
  return $addresses
}

proc ::cluster::query_id {} {
  return [incr ::cluster::i]
}

proc ::cluster::ifhook {hooks args} {
  if { [dict exists $hooks {*}$args] } {
    tailcall dict get $hooks {*}$args
  }
}