if { [info commands ::onError] eq {} } {
  # Our Error Handler is called throughout.  If not defined, we define it
  # here.
  # TODO: Provide official way to handle the logging / errors.
  proc ::onError { result options args } {}
}

if {[info commands %] eq {}} {
  # [%] is unfortunately required to be provided this way.  While
  # this may cause side effects until the pre-processor is finished,
  # it is used as a standard for inline documentation throughout
  # Dash Packages.
  proc % args {}
}

% {
  @ ::cluster::rand @
    | Generate a "random" number within the given range
  @arg min {entier} | minimum value
  @arg max {entier} | maximum value
}
proc ::cluster::rand {min max} {
  expr { int(rand() * ($max - $min + 1) + $min)}
}


proc ::cluster::query_id {} { incr ::cluster::i }

proc ::cluster::ifhook {hooks args} {
  if { [dict exists $hooks {*}$args] } {
    tailcall dict get $hooks {*}$args
  }
}
