# Each of these procedures are called and utilized which are platform-specific.

# Any dependencies based on the platform should be included here.
switch -- $::tcl_platform(platform) {
  unix { package require tuapi }
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

# Get the local addresses for this system.
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
