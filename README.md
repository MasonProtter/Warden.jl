# Warden.jl

Warden.jl is an experimental package that provides utilities for allocating a chunk of memory, using it within a fixed scope, and being guarenteed that the allocated memory will be deterministically destructed at the end of the block, either via an `alloca` in the case of a static size specification or with `malloc`/`free` for dynamially specified sizes.

Warden.jl uses Julia's interprocedural escape analysis machinery to prove that the allocated memory will not escape. If it cannot provide such a proof, it will throw a compile-time error.

Safe usage:
``` julia
julia> using Warden

julia> no_escape(Float64, 10) do v
           for i ∈ eachindex(v)
               v[i] = i
           end
           sum(v)
       end
55.0
```

Unsafe usage caught:

``` julia
julia> const store = Ref{Any}();

julia> no_escape(Float64, 1) do v
           store[] = v # This is naughty!
           length(v) + 1
       end
ERROR: EscapeError: You've let an argument you used in `no_escape` escape the function body. Here is the compiler escape analysis result:
#2(X v::Warden.WardedArray{Float64, 1, Base.RefValue{Nothing}}) in Main at REPL[3]:2
◌  1 ─        builtin Base.setfield!(Main.store, :x, _2)::Warden.WardedArray{Float64, 1, Base.RefValue{Nothing}}
X  │   %2 =   builtin Base.getfield(_2, :size)::Tuple{Int64}
X  │   %3 =   builtin Core.getfield(%2, 1)::Int64
◌  │   %4 = intrinsic Base.add_int(%3, 1)::Int64
◌  └──      return %4

Stacktrace:
 [1] __check_escapes(world::UInt64, mthd::Method, this::Type, fargtypes::Tuple{DataType, DataType})
   @ Warden ~/Nextcloud/Julia/Warden/src/Warden.jl:118
 [2] check_escapes(f::Function, v::Warden.WardedArray{Float64, 1, Base.RefValue{Nothing}})
   @ Warden ~/Nextcloud/Julia/Warden/src/Warden.jl:107
 [3] no_escape(f::Function, ::Type{Float64}, sz::Int64)
   @ Warden ~/Nextcloud/Julia/Warden/src/Warden.jl:76
 [4] top-level scope
   @ REPL[3]:1
```


Some benchmarks: 

Static size:

``` julia
julia> @benchmark no_escape(Float64, Val(32)) do v
           v .= 1
           sum(v)
       end
BenchmarkTools.Trial: 10000 samples with 999 evaluations per sample.
 Range (min … max):  11.462 ns … 26.305 ns  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     12.085 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   12.637 ns ±  1.693 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▁▂ █▆▁                       ▂▁         ▂                   ▁
  ██▅███▇▇▇▇█▇▇▇████▇▇█▇▇█▇▇▇█████▅▅▆▆▆▄▆▆█▅▇▆▆▅▄▃▄▃▃▁▄▅▅▅▅▄▃ █
  11.5 ns      Histogram: log(frequency) by time      20.9 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

Dynamic size using `malloc`/`free`:

```julia
julia> @benchmark no_escape(Float64, 32) do v
           v .= 1
           sum(v)
       end
BenchmarkTools.Trial: 10000 samples with 996 evaluations per sample.
 Range (min … max):  26.477 ns … 46.397 ns  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     26.979 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   27.089 ns ±  0.651 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

        ▅█▇▅▄▁▁▂▄▃▃▁                                          ▂
  ▇█▇▄▁▁█████████████▄▄▃▃▃▄▃▄▁▁▁▃▃▁▃▁▁▁▃▁▁▁▃▁▁▁▁▃▃▃▃▁▃▁▁▁▆▄▄▄ █
  26.5 ns      Histogram: log(frequency) by time      30.2 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

Dynamic size with Bumper.jl allocators:

```julia
julia> using Bumper: default_buffer, SlabBuffer, AllocBuffer

julia> @benchmark no_escape(Float64, 32; buffer) do v
           v .= 1
           sum(v)
       end setup=(buffer=$(default_buffer()))
BenchmarkTools.Trial: 10000 samples with 998 evaluations per sample.
 Range (min … max):  15.861 ns … 32.074 ns  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     16.294 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   16.433 ns ±  0.967 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

      █▃                                                       
  ▃▂▂▃██▇▅▃▂▂▂▂▂▁▁▁▂▂▂▂▁▁▂▂▂▁▁▂▂▁▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▁▂ ▂
  15.9 ns         Histogram: frequency by time        20.9 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark no_escape(Float64, 32; buffer) do v
           v .= 1
           sum(v)
       end setup=(buffer=$(default_buffer(AllocBuffer)))
BenchmarkTools.Trial: 10000 samples with 999 evaluations per sample.
 Range (min … max):  13.098 ns … 23.618 ns  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     13.529 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   13.601 ns ±  0.620 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

          █                                                    
  ▂▂▂▂▂▂▇▇█▆▆▄▄▃▂▂▁▁▁▂▁▂▂▁▂▁▁▂▁▁▁▂▂▁▂▂▁▁▂▁▁▁▁▁▂▁▂▁▁▂▁▂▂▂▁▂▁▂▂ ▂
  13.1 ns         Histogram: frequency by time          16 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

____________

For comparison, here's the same benchmark using `Memory`:

```julia
julia> @benchmark let v= Memory{Float64}(undef, 32)
           v .= 1
           sum(v)
       end
BenchmarkTools.Trial: 10000 samples with 998 evaluations per sample.
 Range (min … max):  14.051 ns …  3.165 μs  ┊ GC (min … max):  0.00% … 98.50%
 Time  (median):     22.050 ns              ┊ GC (median):     0.00%
 Time  (mean ± σ):   29.199 ns ± 61.733 ns  ┊ GC (mean ± σ):  21.74% ± 10.88%

  ▆█▃▂                                                        ▁
  ████▇▆▅▁▁▁▄▅▅▅▁▃▃▁▁▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▃▁▄▅▆▆▆ █
  14.1 ns      Histogram: log(frequency) by time       414 ns <

 Memory estimate: 288 bytes, allocs estimate: 1.
```

And `Array`

``` julia
julia> @benchmark let v= Array{Float64}(undef, 32)
           v .= 1
           sum(v)
       end
BenchmarkTools.Trial: 10000 samples with 998 evaluations per sample.
 Range (min … max):  17.237 ns …   7.003 μs  ┊ GC (min … max):  0.00% … 97.88%
 Time  (median):     26.765 ns               ┊ GC (median):     0.00%
 Time  (mean ± σ):   42.725 ns ± 134.868 ns  ┊ GC (mean ± σ):  29.57% ± 12.32%

  ▅█▅▅▅▂▁                                                      ▁
  ████████▆█▇▅▄▃▆▆▇▅▄▃▁▃▁▁▄▃▁▄▁▁▁▃▁▁▁▁▁▁▃▁▁▁▁▁▁▁▄▅▆▅▆▇▆▄▅▅▄▄▁▄ █
  17.2 ns       Histogram: log(frequency) by time       367 ns <

 Memory estimate: 320 bytes, allocs estimate: 2.
```
