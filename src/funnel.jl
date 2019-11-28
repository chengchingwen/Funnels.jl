# function remotevalue_from_id(id)
#   rv = lock(Distributed.client_refs) do
#     return get(Distributed.PGRP.refs, id, false)
#   end
#   if rv === false
#     throw(ErrorException("Local instance of remote reference not found"))
#   end
#   return rv
# end

separate!(src::Channel, dests; ctype=Any, csize=0) = separate!(RemoteChannel(()->src, myid()), dests; ctype=ctype, csize=csize)
function separate!(src::RemoteChannel, dests; ctype=Any, csize=0)
  n = length(dests)
  return @channels n=length(dests) remote=true pid=dests ctype=ctype csize=csize begin
    while true
      v = @try_take! src break
      put!(_, v)
    end
  end
end

function collect!(srcs::Container{RemoteChannel}, dest; ctype=Any, csize=0)
  res = RemoteChannel(()->Channel{ctype}(csize), dest)
  fins = map(srcs) do rc
    remotecall(rc.where) do
      chn = channel_from_id(Distributed.remoteref_id(rc))
      for v in chn
        put!(res, v)
      end
    end
  end
  remote_do(res.where) do
    task = @async wait.(fins)
    bind(Distributed.channel_from_id(Distributed.remoteref_id(res)), task)
  end
  res
end

funnel(f::Function, inc::ChannelLike, args...; kwargs...) = funnel(push!, f, inc, args...; kwargs...)
function funnel(p::typeof(push!), f::Function, inc::ChannelLike, args...; csize=0, ctype=Any, kwargs...)
  return @channel csize=csize ctype=ctype remote=false begin
    while true
      v = @try_take! inc break
      put!(_, f(v, args...; kwargs...))
    end
  end
end

function funnel(p::typeof(take!), f::Function, inc::ChannelLike, args...; csize=0, ctype=Any, kwargs...)
  return @channel csize=csize ctype=ctype remote=false begin
    while true
      v = @try_call! f(inc, args...; kwargs...) break
      put!(_, v)
    end
  end
end

function funnel(p::typeof(put!), f::Function, inc::ChannelLike, args...; csize=0, ctype=Any, kwargs...)
  return @channel csize=csize ctype=ctype remote=false begin
    while true
      v = @try_take! inc break
      f(_, v, args...; kwargs...)
    end
  end
end

const Phase = Union{typeof(put!), typeof(take!), typeof(push!)}

stage!(f, rc::RemoteChannel, args...; kwargs...) = stage!(push!, f, rc, args...; kwargs...)
function stage!(p::Phase, f, rc::RemoteChannel, args...; kwargs...)
  rrid = Distributed.remoteref_id(rc)
  remote_do(rc.where, rrid) do id
    lock(Distributed.client_refs) do
      rv = get(Distributed.PGRP.refs, id, false)
      rv.c = funnel(p, f, channel_from_id(id), args...; kwargs...)
    end
  end
  rc
end

stage!(f, rcs::Container{RemoteChannel}, args...; kwargs...) = stage!(push!, f, rcs, args...; kwargs...)
function stage!(p::Phase, f, rcs::Container{RemoteChannel}, args...; kwargs...)
  map(rcs) do rc
    stage!(p, f, rc, args...; kwargs...)
  end
end
