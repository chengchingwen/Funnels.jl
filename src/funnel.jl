function remotevalue_from_id(id)
  rv = lock(Distributed.client_refs) do
    return get(Distributed.PGRP.refs, id, false)
  end
  if rv === false
    throw(ErrorException("Local instance of remote reference not found"))
  end
  return rv
end

function separate!(src::RemoteChannel, dests; kw...)
  rcs = Vector{RemoteChannel}(undef, length(dests))
  for (i, pid) in enumerate(dests)
    rc = RemoteChannel(
      ()->Channel(; kw...) do c
        while true
          v = @try_take! src break
          put!(c, v)
        end
      end,
      pid)
    rcs[i] = rc
  end
  rcs
end

function collect!(srcs::Vector{RemoteChannel}, dest; ctype=Any, csize=0)
  res = RemoteChannel(()->Channel{ctype}(csize), dest)
  fins = map(srcs) do rc
    pid = rc.where
    remotecall(pid) do
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

function funnel(p::typeof(take!), f, inc, args...; csize=0, ctype=Any, kwargs...)
  outc = Channel{ctype}(csize)
  task = @async while true
    v = @try_call! f(inc, args...; kwargs...) break
    put!(outc, v)
  end
  bind(outc, task)
  outc
end

function funnel(p::typeof(put!), f, inc, args...; csize=0, ctype=Any, kwargs...)
  outc = Channel{ctype}(csize)
  task = @async while true
    v = @try_take! inc break
    put!(outc, f(v, args...; kwargs...))
  end
  bind(outc, task)
  outc
end

stage!(f, rc::RemoteChannel, args...; kwargs...) = stage!(Put, f, rc::RemoteChannel, args...; kwargs...)

function stage!(p::Union{typeof(put!), typeof(take!)}, f, rc::RemoteChannel, args...; kwargs...)
  pid = rc.where
  remote_do(pid) do
    rv = remotevalue_from_id(Distributed.remoteref_id(rc))
    rv.c = funnel(p, f, rv.c, args...; kwargs...)
  end
  rc
end

function stage!(p::Union{typeof(put!), typeof(take!)}, f, rcs::Vector{RemoteChannel}, args...; kwargs...)
  map(rcs) do rc
    stage!(p, f, rc, args...; kwargs...)
  end
end
stage!(f, rcs::Vector{RemoteChannel}, args...; kwargs...) = stage!(put!, f, rcs, args...; kwargs...)

function batches!(c::Channel, n=1)
  res = []
  sizehint!(res, n)
  for i = 1:n
    v = @try_take! c if isempty(res)
      rethrow()
    else
      break
    end
    push!(res, v)
  end
  res
end

function merges!(cs::Vector{C}; csize=0, ctype=Any) where C <: Channel
  c = Channel(;csize=csize, ctype=ctype) do c
    while true
      v = @try_call! map(cs) do c
        take!(c)
      end break
      put!(c, v)
    end
  end
end
