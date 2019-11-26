module Funnels

using Distributed

export @try_take!, @try_call!,
  @channels, @channel
export separate!, collect!, stage!, merges!, batches!

const ChannelLike{T} = Union{Channel{T}, RemoteChannel{Channel{T}}}
const Container{T} = Union{NTuple{N, T}, Vector{T}} where N

include("./utils.jl")
include("./channel.jl")
include("./funnel.jl")
include("./chn_funcs.jl")

end # module
