namespace eval ::cluster {
  namespace ensemble create
  namespace export {[a-z]*}
}

switch -- $::tcl_platform(platform) {
  unix { package require tuapi }
}

variable ::cluster::i 0
variable ::cluster::default_config [dict create \
  name        [pid] \
  address     230.230.230.230 \
  port        23000 \
  ttl         600000 \
  heartbeat   120000 \
  protocols   [list t c] \
  remote      0
]

namespace eval ::cluster::clusters {}
namespace eval ::cluster::protocol {}
# Build our initial classes.  We do this here so we can easily 
# replace code using definitions later.
::oo::class create ::cluster::cluster {}
::oo::class create ::cluster::service {}

source "./classes/cluster.tcl"
source "./classes/service.tcl"
source "./protocols/cluster-cluster.tcl"
source "./protocols/cluster-tcp.tcl"

proc ::cluster::join args {
  variable i
  set config $::cluster::default_config
  dict for { k v } $args {
    set k [string trimleft $k -]
    if { ! [dict exists $config $k] } {
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
proc ::cluster::islocal { peer } {
  set ip [lindex $peer 0]
  if { $ip eq "127.0.0.1" } { return 1 }
  switch $::tcl_platform(platform) {
    unix {
      dict for { iface params } [::tuapi::ifconfig] {
        if { [dict exists $params address] && [dict get $params address] eq $ip } {
          return 1
        }
      }
    }
  }
  return 0
}

proc ::cluster::ifhook {hooks args} {
  if { [dict exists $hooks {*}$args] } {
    return [dict get $hooks {*}$args] 
  }
}

# Take a $UUID value and split it into its parts, returning a list
# with each part [list $hwaddr $name $protocols]
# 00:1F:B8:2A:01:1F@29246.c.t -> [list 00:1F:B8:2A:01:1F 29246 [list c t]]
proc ::cluster::split_uuid { uuid } {
  lassign [split $uuid @] hwaddr props
  set protocols [lassign [split $props .] name]
  return [list $hwaddr $name $protocols]
}


# Join the default cluster.  If this is called on multiple machines, they will
# immediately begin communicating seeing each other.
# set cluster [cluster join]

# We can define changes to the default configuration by providing -$k $v arguments
# set cluster [cluster join -name my-service]
# set cluster [cluster join -name my-server -port 22000 -protocols [list c t u]

# $cluster on service discovered {
#   # access to $service and $cluster - execute within $cluster namespace
# }

# $cluster on service lost {
#   # access to $service and $cluster - executed within $cluster namespace
# }

# $cluster on error { result options } {
#   # access to $cluster executed within $cluster namespace
# }

# $cluster on service error {result options} {
#   # access to $cluster $service executed within $service namespace.  Throw error
#   # if want to pass the error up to the cluster error handler.
# }

# # Hooks are different from handlers.  The handlers are executed as lambdas while
# # hooks are evaluated as a means of mutating values at various points in the 
# # execution context.
# #
# # Generally these should follow specific guidelines.

# # $op - $ruid - $peer - $service - [self] - [my __] 
# # Error: cancels evaluation of received
# $cluster hook receive {
#   puts "RECEIVED!!"
# }

# # $proto - $op (includes ruid) - $data - $service (if applicable)
# # Error: cancels sending to protocol
# $cluster hook send {
#   puts "SENDING!"
# }

# $cluster hook protocol t receive {
  
# }

# $cluster hook protocol t send {
  
# }

# $cluster hook op <op> receive {
  
# }

# $cluster hook op <op> send {
  
# }

# # $uuid - $peer - $service - $descriptor - $hwaddr - $name - $protocols
# $cluster hook service eval {
  
# }

# # $uuid - $peer - $service - $descriptor - $hwaddr - $name - $protocols
# $cluster hook service validate {
  
# }

# # Called when a service has been discovered
# #
# # $uuid - $peer - $service - $descriptor - $hwaddr - $name - $protocols
# $cluster hook service found {
  
# }

# # Called when a service is lost 
# #
# # $service - Where $service is still a valid service (it has not yet been destroyed)
# $cluster hook service lost {
  
# }

# $cluster sendto [$cluster resolve 192.168.1.60 1] C {set ::status} then { result } {
#   # Do something with each result that we receive Our $result variable is within this
#   # context, as is the $service , $cluster , and other common variables.
# }
