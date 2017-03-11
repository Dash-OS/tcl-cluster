# Currently we just save the hooks without validating them as a supported hook.
# protocol hooks are $protocol send/receive
# global hooks are send/receive
::oo::define ::cluster::cluster method hook args {
  set body [lindex $args end]
  set path [lrange $args 0 end-1]
  dict set HOOKS {*}$path $body
}

# When we want to retrieve the body for a given hook, we call this method with
# the desired hook key.  We will either return {} or the given hooks body to be
# evaluated.
::oo::define ::cluster::cluster method run_hook args {
  if { $HOOKS eq {} } { return }
  tailcall try [::cluster::ifhook $HOOKS {*}$args]
}

::oo::define ::cluster::cluster method is_local { address } {
  if { $address in [::cluster::local_addresses] || [string equal $address localhost] } { 
    return 1 
  } else { return 0 }
}

# Get our scripts UUID to send in payloads
::oo::define ::cluster::cluster method uuid {} { return ${SERVICE_ID}@${SYSTEM_ID} }

# Retrieve how long a service should be cached by the protocol.  If we do not
# hear from a given service for longer than the $ttl value, the service will be 
# removed from our cache.
::oo::define ::cluster::cluster method ttl  {} { return [dict get $CONFIG ttl] }

::oo::define ::cluster::cluster method protocols {} { return [dict get $CONFIG protocols] }

::oo::define ::cluster::cluster method protocol { protocol } {
  if { [dict exists $PROTOCOLS $protocol] } {
    return [dict get $PROTOCOLS $protocol] 
  }
}

::oo::define ::cluster::cluster method props args {
  set props [dict create]
  foreach prop $args {
    if { $prop eq {} } { continue }
    switch -nocase -glob -- $prop {
      protop* - protoprops { set props [my ProtoProps $props] }
    }
  }
  return $props
}

# A list of all the currently known services
::oo::define ::cluster::cluster method services {} {
  return [info commands ${NS}::services::*]
}

::oo::define ::cluster::cluster method known_services {} { llength [my services] }

::oo::define ::cluster::cluster method config { args } {
  return [dict get $CONFIG {*}$args]
}

::oo::define ::cluster::cluster method flags {} { 
  return [ list [my known_services] 0 0 0 ] 
}

# Resolve services by running a search against each $arg to return the 
# filtered services which match every arg. Resolution is a simple "tag-based"
# search which matches against a services given tags.
# set services [$cluster resolve localhost my_service]
::oo::define ::cluster::cluster method resolve args {
  set services [my services]
  foreach filter $args {
    if { $services eq {} } { break }
    set services [lmap e $services { 
      if { [string match "::*" $filter] || [string is true -strict [ $e resolve $filter ]] } {
        set e
      } else { continue }
    }]
  }
  return $services
}

# resolver is a more powerful option than resolve which allows adding of some added logic.
# Each argument will define which services we want to match against.
#
# Additionally, we can specify boolean-type modifiers which will change the behavior.  These
# are applied IN ORDER so for example if we run -match after -has then has will not use match
# but any queries after will.
#
# Modifiers:
#  -equal (default)
#   Items will use equality to test for success
#  -match 
#   Items will use string match to test for success
#  -regexp
#   Items will use regexp to test for success on each item

# -has [list]
#   The service must match all items in the list
# -not [list]
#   The service must NOT match any of the items given
# -exact [list]
#   The service must have every item in the list and no others
# -some [list]
#   The service must match at least one item in the list
#
# Examples:
#  $cluster resolver -match -has [list *wait] -equal -some [list one two three]
::oo::define ::cluster::cluster method resolver args {
  set modifier equal
  set services [my services]
  foreach filter [split $args -] {
    if { $filter eq {} } { continue }
    if { [llength $services] == 0 } { break }
    lassign $filter opt tags
    if { $tags eq {} } { set modifier $opt } else {
      set services [lmap e $services {
        if { [string is true -strict [$e resolver $tags $modifier $opt]] } {
          set e
        } else { continue }
      }]
    }
  }
  return $services
}

# Resolve ourselves
::oo::define ::cluster::cluster method resolve_self args {
  foreach filter $args {
    if { $filter eq {} } { continue }
    if { $filter in $TAGS } { continue }
    if { [string equal $filter $SERVICE_ID] } { continue }
    if { [string equal $filter $SYSTEM_ID]  } { continue}
    # 127.0.0.1 or LAN IP's
    if { [my is_local $filter] } { continue }
    return 0
  }
  return 1
}

# Tags are sent to clients to give them an idea for what each service provides or
# wants other services to be aware of.  Tags are sent only when changed or when requested.
::oo::define ::cluster::cluster method tags { {action {}} args } {
  if { $action eq {} } { return $TAGS }
  set prev_tags $TAGS
  if { [string equal [string index $action 0] -] } {
    set action [string trimleft $action -]
  } else {
    set args [list $action {*}$args]
    set action {}
  }
  if { $args ne {} } {
    switch -- $action {
      append { lappend TAGS {*}$args }
      remove { 
        foreach tag $TAGS {
          set TAGS [lsearch -all -inline -not -exact $TAGS $tag]
        }
      }
      replace - default { set TAGS $args }
    }
  }
  try [my run_hook tags update] on error {r} {
    # If we receive an error during the hook, we will revert to the previous tags
    set TAGS $prev_tags
  }
  if { $prev_tags ne $TAGS } {
    # If our tags change, our change hook will fire
    set UPDATED_PROPS [concat $UPDATED_PROPS [list tags]]
    try [my run_hook tags changed] on error {r} {
      # We don't do anything if this produces error, use update for that.  This
      # should be used when a tag update is accepted, for example if we wanted to
      # then broadcast to the cluster with our updated tags.
    }
  }
  return $TAGS
}

::oo::define ::cluster::cluster method channel { action channels } {
  switch -nocase -- $action {
    subscribe - enter - join - add {
      foreach channel $channels {
        if { $channel ni $COMM_CHANNELS } {
          lappend COMM_CHANNELS $channel
        }
      }
    }
    unsubscribe - exit - leave - remove {
      foreach channel $channels {
        if { $channel in [list 0 1 2] } { throw error "You may not leave the default channels 0-2" }
        if { $channel in $COMM_CHANNELS } {
          set COMM_CHANNELS [lsearch -all -inline -not -exact $COMM_CHANNELS $channel]
        }
      }
    }
  }
}
