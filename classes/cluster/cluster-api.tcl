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

::oo::define ::cluster::cluster method hid {} { return $SYSTEM_ID  }
::oo::define ::cluster::cluster method sid {} { return $SERVICE_ID }
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
::oo::define ::cluster::cluster method resolve {filters args} {
  set services [my services]
  foreach filter [concat $filters $args] {
    if { $services eq {} } { break }
    set services [lmap e $services { 
      if { 
        ( [string match "::*" $filter] && [info commands $filter] ne {} )
        || [ string is true -strict [ $e resolve $filter ] ]
      } { set e } else { continue }
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
  # In case we want to feed as a single value rather than a args list
  try {
    if { [llength $args] == 1 } { set args [lindex $args 0] }
    if { [string index [string trim $args] 0] ne "-" } {
      # We want to use regular resolve
      return [my resolve $args]
    }
    set modifier equal
    set op {}
    set services [my services]
    foreach filter $args {
      if { $filter eq {} } { continue }
      if { [llength $services] == 0 } { break }
      if { [string index $filter 0] eq "-" } {
        set opt [string trimleft $filter "-"]
        switch -glob -- $opt {
          equal - match - regex* {
            set op {}
            set modifier $opt
          }
          default { set op $opt }
        }
        continue
      }
      # This allows modifiers in object form { "-match": 1 }
      if { $filter == 1 } { continue }
      set services [lmap e $services {
        if { [string is true -strict [$e resolver $filter $modifier $op]] } {
          set e
        } else { continue }
      }]
    }
  } on error {result options} {
    ::onError $result $options "While Resolving Cluster Services" $args
    if { ! [info exists services] } { set services {} }
  }
  return $services
}

# Resolve ourselves
::oo::define ::cluster::cluster method resolve_self { tag {modifier equal} } {
  switch -- $modifier {
    equal { 
      if { $tag in $TAGS } { return 1 }
      if { [string equal $tag $SERVICE_ID] } { return 1 }
      if { [string equal $tag $SYSTEM_ID]  } { return 1 } 
      if { [my is_local $tag] } { return 1 }
    }
    match { 
      foreach _tag $TAGS { if { [string match $tag ${_tag}] } { return 1 } }
      if { [string match $tag $SERVICE_ID] } { return 1 }
      if { [string match $tag $SYSTEM_ID]  } { return 1 }
      # We dont match against the my islocal data at this time
    }
    regex {
      # Not Finished
    }
  }
  return 0
}

::oo::define ::cluster::cluster method resolver_self args {
  if { [llength $args] == 1 } { set args [lindex $args 0] }
  set modifier equal
  set op {} ; set opt has
  foreach filter $args {
    if { $filter eq {} } { continue }
    if { [string index $filter 0] eq "-" } {
      set opt [string trimleft $filter "-"]
      switch -glob -- $opt {
        equal - match - regex* {
          set op {}
          set modifier $opt
        }
        default { set op $opt }
      }
      continue
    }
    # This allows modifiers in object form { "-match": 1 }
    if { $filter == 1 } { continue }
    switch -- $opt {
      all - has {
        # Must match every tag
        foreach tag $filter { 
          if { ! [my resolve_self $tag $modifier] } { return 0 } 
        }
        return 1
      }
      not {
        # Must not match any of the tags
        foreach tag $filter { 
          if { [my resolve_self $tag $modifier] } { return 0 } 
        }
        return 1
      }
      some {
        # Must have at least one $what
        foreach tag $filter { 
          if { [my resolve_self $tag $modifier] } { return 1 } 
        }
      }
    }
  }
  return 0
}

# Tags are sent to clients to give them an idea for what each service provides or
# wants other services to be aware of.  Tags are sent only when changed or when requested.
# $cluster tags -append tag0 tag1 -map {tag1 tag2} -remove tag2 -append tag3 tag4
# % tag0 tag3 tag4
::oo::define ::cluster::cluster method tags { args } {
  if { $args eq {} } { return $TAGS }
  set prev_tags $TAGS
  set action append
  foreach arg $args {
    if { [string equal [string index $arg 0] -] } {
      set action [string trimleft $arg -]
      continue
    }
    switch -- $action {
      map {
        # -map [list one two] - switch lindex 0 with lindex 1
        set prev [lindex $arg 0]
        set next [lindex $arg 1]
        if { $next ne {} } {
          set index [lsearch $TAGS $prev]
          if { $index != -1 } {
            set TAGS [lreplace $TAGS $index $index $next]
          }
        }
      }
      mappend {
        # similar to -map except that it will add the second tag even if the
        # first does not exist
        set prev [lindex $arg 0]
        set next [lindex $arg 1]
        if { $prev in $TAGS } {
          set TAGS [lsearch -all -inline -not -exact $TAGS $prev]
        }
        if { $next ne {} && $next ni $TAGS } { lappend TAGS $next }
      }
      remove {
        if { $arg in $TAGS } {
          set TAGS [lsearch -all -inline -not -exact $TAGS $arg]
        }
      }
      replace {
        # -replace will replace the tags with this arg then switch to append for
        # any tags after it
        set action append
        set TAGS $arg
      }
      lappend - append {
        if { $arg ne {} && $arg ni $TAGS } { lappend TAGS $arg }
      }
    }
  }
  if { $prev_tags ne $TAGS } {
    # If our tags change, our change hook will fire
    if { "tags" ni $UPDATED_PROPS } {
      lappend UPDATED_PROPS tags
    }
  }
  # For now, we will heartbeat after changing tags so our partners get the
  # new tags immediately.
  after 0 [callback my heartbeat]
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
