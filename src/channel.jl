macro channel(_ex...)
  kws = Dict{Symbol, Any}(
    :ctype=>Any,
    :csize=>0,
    :remote=>false,
    :pid=>myid(),
  )
  for i = 1:length(_ex)-1
    mkw = _ex[i]
    if mkw isa Expr && mkw.head == :(=)
      if haskey(kws, mkw.args[1])
        if mkw.args[2] isa Number
          kws[mkw.args[1]] = mkw.args[2]
        else
          kws[mkw.args[1]] = :($(esc(mkw.args[2])))
        end
      else
        return Expr(:call, :error, "Invalid keyword argument: $(mkw.args[1])")
      end
    else
      return Expr(:call, :error, "channel expects only one non-keyword argument")
    end
  end

  set_channel_symbol!(x, s) = nothing
  set_channel_symbol!(ex::Expr, s) =
    for i = 1:length(ex.args)
      ms = ex.args[i]
      if ms isa Symbol && ms === :_
        ex.args[i] = s
        return
      else
        set_channel_symbol!(ex.args[i], s)
      end
    end

  ex = _ex[end]
  ex = (ex isa Expr && ex.head == :block) ? ex : Expr(:block, ex)
  ctype = kws[:ctype]
  csize = kws[:csize]
  remote = kws[:remote]
  pid = kws[:pid]

  c = gensym(:c)
  set_channel_symbol!(ex, c)

  chnc = Expr(:do,
              :(Channel(;ctype=$(ctype), csize=$(csize))),
              Expr(:(->),
                   Expr(:tuple, esc(c)),
                   esc(ex)
                   )
              )


  if remote isa Bool
    if remote
      return :(RemoteChannel(()->$chnc, $pid))
    else
      return chnc
    end
  else
    return :($remote ? RemoteChannel(()->$chnc, $pid) : $chnc)
  end
end


islist(ex) = false
islist(ex::Expr) = ex.head == :tuple || ex.head == :vect
function listize(name, x, n)
  if islist(x)
    if length(x.args) == n
      return map(arg->arg isa Number ? arg : :($(esc(arg))), x.args)
    else
      return Expr(:call, :error, "keyword argument $name length not matched: $(length(x.args)) v.s. $n (expected)")
    end
  else
    if x isa Number
      return fill(x, n)
    else
      return fill(:($(esc(x))), n)
    end
  end
end

macro channels(_ex...)
  kws = Dict{Symbol, Any}(
    :ctype=>Any,
    :csize=>0,
    :remote=>false,
    :pid=>myid(),
  )
  n = 0

  for i = 1:length(_ex)-1
    mkw = _ex[i]
    if mkw isa Expr && mkw.head == :(=)
      if haskey(kws, mkw.args[1])
        kws[mkw.args[1]] = mkw.args[2]
      elseif mkw.args[1] == :n
        n = mkw.args[2]
      else
        return Expr(:call, :error, "Invalid keyword argument: $(mkw.args[1])")
      end
    else
      return Expr(:call, :error, "channel expects only one non-keyword argument")
    end
  end

  ex = _ex[end]

  if n == 0
    return Expr(:call, :error, "missing keyword argument: n must be specified")
  end

  if n isa Int
    for (kw, vl) in kws
      mv = listize(kw, vl, n)
      if mv isa Expr
        return mv
      else
        kws[kw] = mv
      end
    end

    chns = []
    for i in 1:n
      d = []
      kws[:ctype][i] != Any && push!(d,  Expr(:(=), :ctype, kws[:ctype][i]))
      kws[:csize][i] != 0 && push!(d, Expr(:(=), :csize, kws[:csize][i]))
      kws[:remote][i] && push!(d, Expr(:(=), :remote, kws[:remote][i]))
      kws[:remote][i] && push!(d, Expr(:(=), :pid, kws[:pid][i]))

      push!(chns,
            Expr(
              :macrocall,
              Symbol("@channel"),
              Base.LineNumberNode(1),
              d...,
              ex
            )
            )
    end
    return Expr(:tuple, chns...)
  else
    return Expr(:call, :error, "n cannot be known at parsing time")
  end
end

get_channels(::Type{T}; buffer_size=0) where T = Channel{T}(buffer_size)
function get_channels(::Type{T}, n; buffer_size=0) where T
    Tuple(Channel{T}(buffer_size) for i = 1:n)
end



