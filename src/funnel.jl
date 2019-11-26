function remotevalue_from_id(id)
  rv = lock(Distributed.client_refs) do
    return get(Distributed.PGRP.refs, id, false)
  end
  if rv === false
    throw(ErrorException("Local instance of remote reference not found"))
  end
  return rv
end

separate!(src::Channel, dests; ctype=Any, csize=0) = separate!(RemoteChannel(()->src, myid()), dests; ctype=ctype, csize=csize)
function separate!(src::RemoteChannel, dests; ctype=Any, csize=0)
  n = length(dests)
  return @channels n=length(dests) remote=true pid=dests ctype=ctype csize=csize begin
    while true
      v = @try_take! src break
      put!(_, v)
    end
  end
  # rcs = Vector{RemoteChannel}(undef, length(dests))
  # for (i, pid) in enumerate(dests)
  #   rc = RemoteChannel(
  #     ()->Channel(; kw...) do c
  #       while true
  #         v = @try_take! src break
  #         put!(c, v)
  #       end
  #     end,
  #     pid)
  #   rcs[i] = rc
  # end
  # rcs
end

function collect!(srcs::Container{RemoteChannel}, dest; ctype=Any, csize=0)
  res = RemoteChannel(()->Channel{ctype}(csize), dest)
  fins = map(srcs) do rc
    remotecall(rc.where) do
      chn = remotevalue_from_id(Distributed.remoteref_id(rc)).c
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

function funnel(p::typeof(take!), f::Function, inc::ChannelLike, args...; csize=0, ctype=Any, kwargs...)
  return @channel csize=csize ctype=ctype remote=false begin
    while true
      v = @try_call! f(inc, args...; kwargs...) break
      put!(_, v)
    end
  end
  # outc = Channel{ctype}(csize)
  # task = @async while true
  #   v = @try_call! f(inc, args...; kwargs...) break
  #   put!(outc, v)
  # end
  # bind(outc, task)
  # outc
end

function funnel(p::typeof(put!), f::Function, inc::ChannelLike, args...; csize=0, ctype=Any, kwargs...)
  return @channel csize=csize ctype=ctype remote=false begin
    while true
      v = @try_take! inc break
      put!(_, f(v, args...; kwargs...))
    end
  end
  # outc = Channel{ctype}(csize)
  # task = @async while true
  #   v = @try_take! inc break
  #   put!(outc, f(v, args...; kwargs...))
  # end
  # bind(outc, task)
  # outc
end

stage!(f, rc::RemoteChannel, args...; kwargs...) = stage!(put!, f, rc, args...; kwargs...)
function stage!(p::Union{typeof(put!), typeof(take!)}, f, rc::RemoteChannel, args...; kwargs...)
  remote_do(rc.where) do
    rv = remotevalue_from_id(Distributed.remoteref_id(rc))
    rv.c = funnel(p, f, rv.c, args...; kwargs...)
  end
  rc
end

stage!(f, rcs::Container{RemoteChannel}, args...; kwargs...) = stage!(put!, f, rcs, args...; kwargs...)
function stage!(p::Union{typeof(put!), typeof(take!)}, f, rcs::Container{RemoteChannel}, args...; kwargs...)
  map(rcs) do rc
    stage!(p, f, rc, args...; kwargs...)
  end
end
