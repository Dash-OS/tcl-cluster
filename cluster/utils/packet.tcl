package require bpacket

namespace eval ::cluster {}
namespace eval ::cluster::packet {}

bpacket create io ::cluster::packet::io {
  1  varint  type
  2  varint  channel
  3  string  hid
  4  string  sid
  5  varint  known
  6  varint  timestamp
  7  list    protocols
  8  string  ruid
  9  string  op
  10 string  data
  11 raw     raw
  12 list    tags
  13 boolean keepalive
  14 list    filter
  15 string  error
}

proc ::cluster::packet::encode { payload } {
  set encoded [io encode $payload]
  return $encoded
}

proc ::cluster::packet::decode { packet {cluster {}} } {
  return [io decode $packet \
    -validate [list ::apply {
      {cluster field} {
        # break        - stop parsing, return packet as is
        # continue     - do not include field
        # return false - stop parsing, return empty packet
        # error        - throw given error
        # else         - add field to packet by name and id
        # notes:
        #   - modify field with   upvar field   if needed
        #   - modify results with upvar results if needed
        switch -- [dict get $field id] {
          14 {
            # check the filter and only continue if we match
            if {$cluster ne {} && ! [$cluster check_filter $data]} {
              return false
            }
          }
        }
      }
    } $cluster]
  ]
}

# TODO: trash this once we confirm the above rewrite is working
# try {
#   # ~! "Decode Packet" "Decoding a Packet [string bytelength $packet]"
#   set reader  [::bpacket::reader new $packet]
#   set result  [dict create]
#   set results [list]
#   set active 1
#   while {$active} {
#     lassign [$reader next] active id type data
#     switch -- $active {
#       0 {
#         # We are done parsing the packet!
#         lappend results $result
#         break
#       }
#       1 {
#           # We have more to parse!
#           switch -- $id {
#           1  {
#             lassign $data type channel
#             dict set result type $type
#             dict set result channel $channel
#           }
#           2  { dict set result hid $data }
#           3  { dict set result sid $data }
#           4  { dict set result flags $data }
#           5  { dict set result timestamp $data }
#           6  { dict set result protocols $data }
#           7  { dict set result ruid $data }
#           8  { dict set result op $data }
#           9  { dict set result data $data }
#           10 { dict set result raw $data }
#           11 { dict set result tags $data }
#           12 { dict set result keepalive $data }
#           13 {
#             # When we receive a filter we will immediately try to check with the
#             # cluster if our service matches and quit decoding immediately if we
#             # dont.
#             if { $cluster ne {} && ! [$cluster check_filter $data] } {
#               break
#             }
#             dict set result filter $data
#           }
#           14 {
#             dict set result error $data
#           }
#         }
#       }
#       2 {
#         # We are done with a packet -- but another might still be
#         # available!
#         lappend results $result
#         set result [dict create]
#       }
#     }
#   }
#   $reader destroy
# } on error {result options} {
#   puts stderr "Malformed Packet! $result"
#   catch { ::onError $result $options "Malformed Packet!" }
#   catch { $reader destroy }
# }
# if { $active } {
#   set result {}
# }
