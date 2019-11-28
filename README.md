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

Since the data are not executed in order, the data in each batches will not have any order. However, we can do this to remain the order.
```julia
using Distributed
addprocs(4)
@everywhere using Funnels

batch_size = 5

# data source
c = Funnels.@channel foreach(i->put!(_, i), 1:100)

# batched to mantain order in batch
cout = funnel(take!, batches!, c, batch_size)

# separate data from `cout` to three process with id [3, 4, 5]
pipes = separate!(cout, [3,4,5]; csize=5)

# take out data from batches on each process
stage!(put!, unbatches!, pipes)

# processing
stage!(i->i*i, pipes)
stage!(i->i+10000, pipes[2])

# take data in batches 
stage!(take!, batches!, pipes, batch_size)

# collect data on local process from each process
m = collect!(pipes, myid())

julia> while true
           v = Funnels.@try_take! m break
           @show v
       end
v = Any[3721, 3844, 3969, 4096, 4225]
v = Any[1, 4, 9, 16, 25]
v = Any[10961, 11024, 11089, 11156, 11225]
v = Any[4356, 4489, 4624, 4761, 4900]
v = Any[11296, 11369, 11444, 11521, 11600]
v = Any[6561, 6724, 6889, 7056, 7225]
v = Any[7396, 7569, 7744, 7921, 8100]
v = Any[36, 49, 64, 81, 100]
v = Any[11681, 11764, 11849, 11936, 12025]
v = Any[121, 144, 169, 196, 225]
v = Any[12116, 12209, 12304, 12401, 12500]
v = Any[256, 289, 324, 361, 400]
v = Any[12601, 12704, 12809, 12916, 13025]
v = Any[441, 484, 529, 576, 625]
v = Any[13136, 13249, 13364, 13481, 13600]
v = Any[676, 729, 784, 841, 900]
v = Any[5041, 5184, 5329, 5476, 5625]
v = Any[15776, 15929, 16084, 16241, 16400]
v = Any[8281, 8464, 8649, 8836, 9025]
v = Any[9216, 9409, 9604, 9801, 10000]
```
