@inline iscall(ex) = false
@inline iscall(ex::Expr) = ex.head == :call

@inline islocalclose(e) = e isa InvalidStateException && e.state == :closed
@inline isremoteclose(e, chn) = e isa RemoteException && e.pid == chn.where && islocalclose(e.captured.ex)
@inline isclose(e, chn) = islocalclose(e) || isremoteclose(e, chn)

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
        v = take!($(chn))
      catch e
        if isclose(e, $(chn))
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
        v = $(call)
      catch e
        if isclose(e, $(chn))
          $(esc(ex))
        else
          rethrow()
        end
      end
    end
  end
end
