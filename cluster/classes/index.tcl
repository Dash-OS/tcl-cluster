proc ::cluster::source_classes {} {
  set directory [file dirname [file normalize [info script]]]
  foreach dir [glob -type d -directory $directory *] {
    foreach file [glob -directory $dir *.tcl] {
      uplevel #0 [list source $file]
    }
  }
  rename ::cluster::source_classes {}
}

::cluster::source_classes