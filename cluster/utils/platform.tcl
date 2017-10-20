namespace eval ::cluster {}

if 0 {
  @type > NetworkInterface {entier|string}
    | Either an interface number or interface name
    @entier
      We will use it with the platforms interface prefix to
      provide the given interface.
    @string
      Provide the exact interface name that should be used.

  @type > SystemPlatform {osx|linux}
    | Returns the expected system platform which should then
    | be used to run the appropriate comands for each of the
    | cluster utilities.
}

if 0 {
  > Platform Dependencies Inclusion
    | Any dependencies based on the platform should be included here.
  TODO:
    Add support for other platforms such as windows.
}
switch -- $::tcl_platform(platform) {
  unix {
    package require unix
    # unix requires tuapi if possible
  }
}

if 0 {
  @ ::cluster::platform @
  @returns {SystemPlatform}
}
proc ::cluster::platform {} {
  switch -nocase -- $::tcl_platform(platform) {
    unix { return [unix platform] }
    default {
      return $::tcl_platform(platform)
    }
  }
}

if 0 {
  @ ::cluster::getInterface @
    | Internal utility used to parse a received "iface" argument
    | and return a valid interface in response.
  @arg platform {SystemPlatform}
  @arg iface {?NetworkInterface?}
}
proc ::cluster::getInterface {platform {iface {}}} {
  switch -- $platform {
    osx {
      if {$iface eq {}} {
        set iface en0
      } elseif {[string is entier -strict $iface]} {
        set iface en$iface
      }
    }
    linux {
      if {$iface ne {}} {
        if {[string is entier -strict $iface]} {
          set iface eth$iface
        }
      }
    }
  }
}


if 0 {
  @ ::cluster::hwaddr @
    | Retrieve the hardware address for the platform.  Currently only
    | handling unix platform.
  @arg iface {?NetworkInterface?}
  @returns {MAC}
}
proc ::cluster::hwaddr {{iface {}}} {
  set mac {}
  switch -- [platform] {
    linux - osx - unix {
      return [unix get mac]
    }
    default {
      # Handle other platforms here
    }
  }
}


if 0 {
  @ ::cluster::lanip @
    | Retrieve the most likely lanip for the platform.  Not currently
    | handling if multiple lan ip's are utilized, we return the first
    | non-loopback address.
  @arg iface {?NetworkInterface?}
    Optionally provide an interface to capture the IP for.  If a
    number is provided, we will use it with the platforms interface
    prefix to provide the given interface.
  @returns {?IP?}
}
proc ::cluster::lanip {{iface {}}} {
  set ip {}
  set platform [::cluster::platform]
  set iface    [::cluster::getInterface $platform $iface]
  switch -- $platform {
    osx {
      # crude method of getting osx lanip for now
      try {
        set ip [exec -ignorestderr -- ipconfig getifaddr $iface]
      } on error {} {} finally {
        if {$ip eq {}} {
          if {$iface ne "en0"} {
            # if fail, default to en0 on osx
            catch {
              set ip [exec -ignorestderr -- ipconfig getifaddr en0]
            }
          }
          if {$ip eq {}} {
            catch {
              set ip [exec -ignorestderr -- ipconfig getifaddr en1]
            }
          }
        }
      }
    }
    linux {
      if {[info commands ::tuapi::ifconfig] ne {}} {
        set ifconfig [::tuapi::ifconfig]
        if {$iface ne {} && [dict exists $ifconfig $iface address]} {
          set ip [dict get $ifconfig $iface address]
        }
      }
    }
    default {
      # handle non unix system here
    }
  }
  # If the above fails to capture the ip we will run the local_addresses
  # command as a fallback attempt.  We will also force a refresh as we
  # want this command to always return the newest LAN IP possible.
  if {$ip eq {}} {
    set addresses [::cluster::local_addresses true]
    if {[llength $addresses] > 1} {
      foreach address $addresses {
        if {$address ne "127.0.0.1" && $address ne "localhost"} {
          set ip $address
          break
        }
      }
    }
  }
  return $ip
}

if 0 {
  @ ::cluster::islocal @
    | Check a {peer} value to see if it is from a local source or not.
  @returns {boolean}
}
proc ::cluster::islocal { descriptor } {
  if { [dict exists $descriptor address] } {
    set address [dict get $descriptor address]
  } else {
    return false
  }
  if {$address in [local_addresses]} {
    return true
  } else {
    return false
  }
}

if 0 {
  @ ::cluster::local_addresses @
    | Capture the LAN IP's of the system which will be used to
    | help determine if a given service is local to the system.
  @arg force {?boolean?}
    By default we cache the results of the command and return
    the cached result if it exists.  Setting force to true will
    force us to refresh the request for the local addresses.
  @returns {list<IP>}
}
proc ::cluster::local_addresses {{force false}} {
  variable addresses
  if { [string is true -strict $force] || ( [info exists addresses] && [llength $addresses] > 2 ) } {
    return $addresses
  }
  set addresses [list localhost 127.0.0.1]
  switch -- [platform] {
    linux - osx {
      if {[info commands ::tuapi::ifconfig] ne {}} {
        dict for { iface params } [::tuapi::ifconfig] {
          if { [dict exists $params address] } {
            set address [dict get $params address]
            if { $address ni $addresses } {
              lappend addresses $address
            }
          }
        }
      } else {
        # attempt to capture using shell commands
        set addresses [split \
          [string map {"addr:" ""} \
            [exec -ignorestderr -- ifconfig | grep -e "inet " | awk "{print \$2}"] \
          ] \
        "\n"]
        if {"localhost" ni $addresses} {
          lappend addresses localhost
        }
        if {"127.0.0.1" ni $addresses} {
          lappend addresses 127.0.0.1
        }
      }
    }
    default {
      # TODO: Handle the situation that we dont know the platform type or
      #       the platform is not handled yet.
    }
  }
  return $addresses
}
