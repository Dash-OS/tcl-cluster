
if 0 {
  @ Platform Dependencies Inclusion
    > Summary
      | Any dependencies based on the platform should be included here.
    TODO:
      Add support for more than simply tuapi.  Need support for
      windows, osx, etc by properly parsing and handling things like
      ifconfig and possibly twapi.
}
switch -- $::tcl_platform(platform) {
  unix {
    try {
      package require tuapi
    } on error {} {
      # We do not have tuapi installed
    }
  }
}

if 0 {
  @ ::cluster::hwaddr
    > Summary
      | Retrieve the hardware address for the platform.  Currently only
      | handling unix platform.
}
proc ::cluster::hwaddr {} {
  switch $::tcl_platform(platform) {
    unix {
      if { [info commands ::tuapi::ifconfig] ne {} } {
        dict for { iface params } [::tuapi::ifconfig] {
          if { ! [string equal $iface lo] && [dict exists $params hwaddr] } {
            return [string toupper [dict get $params hwaddr]]
          }
        }
      }
      # handle if tuapi is not available
    }
  }
}

if 0 {
  @ ::cluster::lanip
    > Summary
      | Retrieve the most likely lanip for the platform.  Not currently
      | handling if multiple lan ip's are utilized, we return the first
      | non-loopback address.
    -returns {lan_ip}
  TODO:
    We likely should return a list of local IP's that should be
    accepted.
}
proc ::cluster::lanip {} {
  switch $::tcl_platform(platform) {
    unix {
      if { [info commands ::tuapi::ifconfig] ne {} } {
        dict for { iface params } [::tuapi::ifconfig] {
          if { ! [string equal $iface lo] && [dict exists $params address] } {
            return [dict get $params address]
          }
        }
      }
      # handle if tuapi is not available
    }
  }
}

if 0 {
  @ ::cluster::islocal
    > Summary
      | Check a $peer value to see if it is from a local source or not.
    -returns {boolean}
      | boolean whether it is local to the system or remote
}
proc ::cluster::islocal { descriptor } {
  if { [dict exists $descriptor address] } {
    set address [dict get $descriptor address]
  } else { return 0 }
  if { $address eq "127.0.0.1" } { return 1 }
  switch $::tcl_platform(platform) {
    unix {
      if { [info commands ::tuapi::ifconfig] ne {} } {
        dict for { iface params } [::tuapi::ifconfig] {
          if { [dict exists $params address] && [dict get $params address] eq $address } {
            return 1
          }
        }
      }
      # handle if tuapi is not available
    }
  }
  return 0
}

if 0 {
  @ ::cluster::local_addresses
    > Summary
      | Called by the framework when we need a list of the local
      | addresses that are associated with this system.
    -refresh {?boolean}
      | Optionally force a refresh of the local addresses
      | value by setting this value to $ true $
}
proc ::cluster::local_addresses {{refresh false}} {
  variable addresses
  if { $addresses ne {} && [string is false -strict $refresh] } {
    return $addresses
  }
  set addresses [list localhost 127.0.0.1]
  switch $::tcl_platform(platform) {
    unix {
      if { [info commands ::tuapi::ifconfig] ne {} } {
        dict for { iface params } [::tuapi::ifconfig] {
          if { [dict exists $params address] } {
            set address [dict get $params address]
            if { $address ni $addresses } { lappend addresses $address }
          }
        }
      }
      # handle if tuapi is not available
    }
  }
  return $addresses
}
