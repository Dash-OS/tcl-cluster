# When we receive a payload from what appears to be the service, we will validate
# against the service to determine if we should accept the payload or not.  We
# return true/false based on the result.
::oo::define ::cluster::service method validate { proto chanID payload descriptor } {
  dict with payload {}

  if {
         "c" ni $protocols
    ||   $sid ne $SERVICE_ID
    ||   $hid ne $SYSTEM_ID
    || ! [info exists channel]
    || ! [info exists type]
    || ! [info exists protocols]
    || ! [info exists sid]
    || ! [info exists hid]
  } {
    return 0
  }

  set PROTOCOLS $protocols

  if { [$proto proto] eq "c" } {
    # Certain properties we only listen to if they come from the cluster
    # socket (such as address)
    if { [dict get $descriptor address] ne $ADDRESS } {
      #puts "Updating Address! [dict get $descriptor address]"
      set ADDRESS [dict get $descriptor address]
    }
  }

  if { [dict exists $descriptor local] } {
    set LOCAL [dict get $descriptor local]
  } else {
    set LOCAL [$CLUSTER is_local $ADDRESS]
  }

  if { [info exists tags] } {
    if { $tags ne $TAGS } {
      set TAGS $tags
      my hook $payload tags changed
      my SetResolve
    }
  }

  set prevChan [my socket [$proto proto]]

  if { $prevChan ne $chanID } {
    my ChannelEvent open $proto $chanID
  }

  switch -- $channel {
    0 {
      # Broadcast - We always accept this
    }
    1 {
      # System - We only accept from localhost
      if { ! $LOCAL } {
        return 0
      }
    }
    2 {
      # LAN - Need to determine if this is coming from a Local Area Network client
      #puts "TO DO : ADD LAN CHANNEL!"
      if { [string is false $LOCAL] } {
        return 0
      }
    }
    default {
      # Received a Channel Message from Service : How do these rules work?
    }
  }

  return 1
}


# opt = has (default), not, some
# modifier = equal, match, regex
::oo::define ::cluster::service method resolver { tags {modifier equal} {opt has} } {
  switch -- $opt {
    all - has {
      # Must match every tag
      foreach tag $tags {
        if { ! [my resolve $tag $modifier] } {
          return 0
        }
      }
      return 1
    }
    not {
      # Must not match any of the tags
      foreach tag $tags {
        if { [my resolve $tag $modifier] } {
          return 0
        }
      }
      return 1
    }
    some {
      # Must have at least one $what
      foreach tag $tags {
        if { [my resolve $tag $modifier] } {
          return 1
        }
      }
    }
  }
  return 0
}

::oo::define ::cluster::service method resolve { tag {modifier equal} } {
  switch -- $modifier {
    equal {
      return [expr { $tag in $RESOLVER }]
    }
    match {
      foreach resolve $RESOLVER {
        if { [string match $tag $resolve] } {
          return 1
        }
      }
    }
    regex {
      # Not Finished
    }
  }
  return 0
}

::oo::define ::cluster::service method socket { protocol } {
  if { [dict exists $SOCKETS $protocol] } {
    return [dict get $SOCKETS $protocol]
  }
}

::oo::define ::cluster::service method info {} {
  return [dict create \
    last_seen  [my last_seen] \
    address    $ADDRESS \
    props      $PROPS \
    system_id  $SYSTEM_ID \
    service_id $SERVICE_ID \
    tags       $TAGS \
    protocols  $PROTOCOLS
  ]
}

# Our objects accessors
::oo::define ::cluster::service method ip        {} { return $ADDRESS }
::oo::define ::cluster::service method props     {} { return $PROPS   }
::oo::define ::cluster::service method tags      {} { return $TAGS    }
::oo::define ::cluster::service method local     {} { return $LOCAL   }
::oo::define ::cluster::service method hid       {} { return $SYSTEM_ID  }
::oo::define ::cluster::service method sid       {} { return $SERVICE_ID }
::oo::define ::cluster::service method protocols {} { return $PROTOCOLS }
::oo::define ::cluster::service method resolver_tags {} { return $RESOLVER    }

# How many seconds has it been since the last heartbeat was received from the service?
::oo::define ::cluster::service method last_seen {} {
  return [expr { [clock seconds] - $LAST_HEARTBEAT }]
}

::oo::define ::cluster::service method proto_props protocol {
  if { [dict exists $PROPS $protocol] } {
    return [dict get $PROPS $protocol]
  }
}
