module Funnels

using Distributed

export separate!, collect!, stage!, merge!

include("./utils.jl")
include("./channel.jl")
include("./funnel.jl")

end # module
