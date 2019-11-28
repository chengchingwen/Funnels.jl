#bypass julia issue #33972
function _take_ref(rid, caller, args...)
  rv = Distributed.lookup_ref(rid)
    synctake = false
    if myid() != caller && rv.synctake !== nothing
        # special handling for local put! / remote take! on unbuffered channel
        # github issue #29932
        synctake = true
        lock(rv.synctake)
    end

  v = try
    take!(rv, args...)
  catch e
    if synctake
      unlock(rv.synctake)
    end
    rethrow(e)
  end

  isa(v, RemoteException) && (myid() == caller) && throw(v)

    if synctake
        return Distributed.SyncTake(v, rv)
    else
        return v
    end
end

_take!(c::Channel, args...) = take!(c)
_take!(rr::RemoteChannel, args...) = Distributed.call_on_owner(_take_ref, rr, myid(), args...)

@inline iscall(ex) = false
@inline iscall(ex::Expr) = ex.head == :call

@inline islocalclose(e) = e isa InvalidStateException && e.state == :closed
@inline isremoteclose(e, ::Channel) = false
@inline isremoteclose(e, chn::RemoteChannel) = e isa RemoteException && e.pid == chn.where && islocalclose(e.captured.ex)
@inline isclose(e, chn::ChannelLike) = islocalclose(e) || isremoteclose(e, chn)
@inline isclose(e, chns::Container{<: ChannelLike}) = any(Base.Fix1(isclose, e), chns)

haskw(ex::Expr) = length(ex.args) >= 2 && isa(ex.args[2], Expr) && ex.args[2].head == :parameters

function get_first_arg(ex::Expr)
  !iscall(ex) && return nothing
  if haskw(ex)
    if length(ex.args) >= 3
      return ex.args[3]
    else
      return nothing
    end
  else
    if length(ex.args) >= 2
      return ex.args[2]
    else
      return nothing
    end
  end
end

macro try_take!(chn, ex=nothing)
  quote
    let v
      try
        v = _take!($(esc(chn)))
      catch e
        if isclose(e, $(esc(chn)))
          $(esc(ex))
        else
          rethrow()
        end
      end
    end
  end
end

macro try_call!(call::Expr, ex=nothing)
  chn = get_first_arg(call)
  quote
    let v
      try
        v = $(esc(call))
      catch e
        if isclose(e, $(esc(chn)))
          $(esc(ex))
        else
          rethrow()
        end
      end
    end
  end
end
