# tcl cluster

`cluster` is a tcl package which provides a simple light-weight framework for
providing inter-process and inter-machine discovery and communications.  

`cluster`'s evaluation hooks provide powerful extensibility, allowing the programmer to modify 
the general behavior of a cluster to fit their security and/or communications handling needs.

**Package Dependencies**

- [TclUDP](https://sourceforge.net/projects/tcludp/) Extension (v1.0.11 or higher)

**Supported Platforms**

- Linux / Unix
  - Requires [tuapi](http://chiselapp.com/user/rkeene/repository/tuapi/home)

## Key Concepts

`cluster` aims to provide a lightweight modular framework for cluster discovery, communications, 
and coordination.  `cluster` members automatically discover each other and provide its preferred 
protocols for communication.  

In a local environment, it's as simple as having both run `[cluster join]` and awaiting 
discovery.  We can then pass messages and commands between our cluster members.

#### Local and/or Remote Capable

By default, our beacons will be set with a UDP TTL of 0.  This means that our beacons 
will only be heard locally on the system.  We may set the ttl value used by our beacons 
using the `-remote` configuration parameter.  Anything higher than 0 will begin to open
our beacons further out from the machine.

When `-remote` is set to 0, communications will be ignored from any communications originating 
from outside of our localhost.

#### Customizable & Extendable

#### Custom Protocol Handlers


## Quick Example

Lets show the simplest possible example by showing three separate tclsh sessions joining
a cluster and discovering the others.



```tcl
package require cluster
set cluster [cluster join -name service_one]

# Insecurely evaluate whatever we receive with C op
$cluster hook op C receive {
  try $data
}

# Enter the event loop and allow cluster to work
vwait _forever_

# Sometime later...

Hello, Foo!

# And later...

Hello, Bar!

```

```tcl
package require cluster
set cluster [cluster join -name service_two]

# Insecurely evaluate whatever we receive
$cluster hook op C receive {
  try $data
}

# Enter the event loop and allow cluster to work
vwait _forever_

# Sometime later...

Hello, Foo!
```

```tcl
package require cluster
set cluster [cluster join -name service_three]

# Enter the event loop for a little while then check the results
after 30000 { set _awhile_ 1 } ; vwait _awhile_

set services [$cluster services]
# ::*::00:1F:B8:2A:01:1F@service_two ; # truncated
# ::*::00:1F:B8:2A:01:1F@service_one

set ips [$cluster ips]
# 192.168.1.60

$cluster broadcast C { puts "Hello, Foo!" }

# Send over tcp protocol to service_one

$cluster sendto [$cluster resolve service_one] C { puts "Hello, Bar!" }

```


## Hooks

Hooks provide a means to customize the evaluation environment with ***short snippets of 
mutations and additions*** to the regular lifecycle of the package.  Hooks are always 
evaluated within the hooks given context.  

We can modify the behavior at each level by either changing values before they are sent 
or received, or throwing an error to cancel any further handling.


#### `$cluster hook send`

#### `$cluster hook receive`

### Protocol Hooks

#### `$cluster hook protocol <proto> receive`

#### `$cluster hook protocol <proto> send`

### Op Hooks

#### `$cluster hook op <op> receive`

#### `$cluster hook op <op> send`

### Service Hooks

#### `$cluster hook service eval`

#### `$cluster hook service validate`

#### `$cluster hook service found`

#### `$cluster hook service lost`


# cluster-comm
