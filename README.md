# Funnels.jl
A Simple Channel-based distributed pipeline tools

```julia
using Distributed
addprocs(4)
@everywhere using Funnels

# simple macro for defining channel
c = Funnels.@channel foreach(i->put!(_, i), 1:100)

# separate data from `c` to three process with id [3, 4, 5]
pipes = separate!(c, [3,4,5]; ctype=Int, csize=5)

# multiply 5 on each process
stage!(i->i*5, pipes)

# add 100 on second process
stage!(i->i+100, pipes[2])

# take data in batches with 5 data per batch on each process
stage!(take!, batches!, pipes, 5)

# collect data on local process from each process
m = collect!(pipes, myid())

julia> take!(m)
5-element Array{Any,1}:
  5
 10
 15
 20
 25

julia> take!(m)
5-element Array{Any,1}:
 65
 70
 75
 80
 85
```
