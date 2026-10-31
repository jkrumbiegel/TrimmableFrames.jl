using Supposition

const CELL_KEY = Data.OneOf(Data.Integers(-2, 3), Data.Just(missing))
const CELL_WIDE = Data.SampledFrom([-1000, 0, 7, 1000])
const CELL_TEXT = Data.OneOf(Data.SampledFrom(["a", "b", "ab", ""]), Data.Just(missing))
const CELL_VALUE = Data.Integers(-5, 5)
const CELL_FLOAT = Data.OneOf(Data.SampledFrom([0.0, -0.0, 1.0, 2.5, NaN, Inf]), Data.Just(missing))
const CELL_FLAG = Data.Booleans()

const ROW = @composed function row(k = CELL_KEY, w = CELL_WIDE, s = CELL_TEXT, x = CELL_VALUE, y = CELL_FLOAT, b = CELL_FLAG)
    return (k = k, w = w, s = s, x = x, y = y, b = b)
end

const ROWS = Data.Vectors(ROW; min_size = 0, max_size = 12)

function frame_of(side::Module, rows)
    return side.DataFrame(
        k = Union{Missing,Int64}[r.k for r in rows],
        w = Int64[r.w for r in rows],
        s = Union{Missing,String}[r.s for r in rows],
        x = Int64[r.x for r in rows],
        y = Union{Missing,Float64}[r.y for r in rows],
        b = Bool[r.b for r in rows],
    )
end

const GROUP_SETTINGS = [
    :(groupby(df, :k)),
    :(groupby(df, :w)),
    :(groupby(df, :s)),
    :(groupby(df, :x)),
    :(groupby(df, :y)),
    :(groupby(df, :b)),
    :(groupby(df, [:k, :x])),
    :(groupby(df, [:s, :b])),
    :(groupby(df, [:b, :k])),
    :(groupby(df, [:w, :y])),
    :(groupby(df, :k; sort = true)),
    :(groupby(df, :s; sort = true)),
    :(groupby(df, :y; sort = true)),
    :(groupby(df, [:s, :k]; sort = true)),
    :(groupby(df, :k; sort = false)),
    :(groupby(df, [:x, :s]; sort = false)),
    :(groupby(df, :k; skipmissing = true)),
    :(groupby(df, [:k, :s]; skipmissing = true)),
    :(groupby(df, :s; sort = true, skipmissing = true)),
]

const GROUP_OPERATIONS = [
    :(combine(gd, nrow)),
    :(combine(gd, :x => sum => :total, proprow)),
    :(combine(gd, :x => maximum, :x => minimum => :low, :y => first, :s => last)),
    :(combine(gd, :x => (v -> v .+ 1) => :z)),
    :(combine(gd, :y => (v -> v .* 2.0))),
    :(combine(gd, :x, :y)),
    :(combine(gd, [:x, :y] => ByRow((p, q) -> p * q) => :z)),
    :(combine(gd, [:x, :b] => ((p, q) -> sum(p) + count(q)) => :z)),
    :(combine(gd, :x => (v -> (p = sum(v), q = length(v))) => AsTable)),
    :(combine(gd, :x => ByRow(v -> v > 0 ? missing : v) => :z)),
    :(combine(gd, :s => ByRow(v -> v === missing ? "none" : v) => :z)),
    :(combine(gd, :x => sum; keepkeys = false)),
    :(combine(sdf -> nrow(sdf), gd)),
    :(select(gd, :x => sum => :total, :y)),
    :(select(gd, :x => cumsum => :running)),
    :(transform(gd, :x => sum => :total, nrow => :n)),
    :(transform(gd, :x => cumsum => :x)),
    :(transform(gd, [:x, :w] => ByRow(+) => :z)),
    :(subset(gd, :x => v -> v .== maximum(v))),
    :(subset(gd, :y => ByRow(v -> v > 0.5); skipmissing = true)),
]

const FRAME_OPERATIONS = [
    :(select(df, :x, :s => :text, :y => ByRow(v -> v === missing ? 0.0 : v) => :clean)),
    :(select(df, Not(:k), :k)),
    :(select(df, [:x, :w] => (+) => :z, :b)),
    :(select(df, :x => sum, :s)),
    :(transform(df, :x => (v -> v .* 2) => :x, :y => ByRow(string) => :y)),
    :(transform(df, [:k, :x] => ByRow((p, q) -> p + q) => :z)),
    :(combine(df, :x => sum, :y => (v -> count(ismissing, v)) => :gaps)),
    :(subset(df, :x => v -> v .> 0)),
    :(subset(df, :k => ByRow(v -> v > 0))),
    :(subset(df, :k => ByRow(v -> v > 0), :b => ByRow(identity); skipmissing = true)),
    :(subset(df, [:x, :w] => ByRow((p, q) -> p < q))),
    :(vcat(df, df)),
    :(vcat(df, select(df, :x, :s); cols = :union)),
    :(vcat(df, select(df, :x, :s); cols = :intersect)),
    :(vcat(select(df, :x), select(df, :y => :x))),
    :(vcat(select(df, :s => :v), select(df, :k => :v))),
    :(vcat(select(df, :x); source = :from)),
]

const GROUP_FUNCTIONS = [
    (Core.eval(DFSide, :((df, gd) -> $op)), Core.eval(TFSide, :((df, gd) -> $op))) for op in GROUP_OPERATIONS
]
const GROUPINGS = [
    (Core.eval(DFSide, :(df -> $g)), Core.eval(TFSide, :(df -> $g))) for g in GROUP_SETTINGS
]
const FRAME_FUNCTIONS = [
    (Core.eval(DFSide, :(df -> $op)), Core.eval(TFSide, :(df -> $op))) for op in FRAME_OPERATIONS
]

# DataFrames stores an all-missing result as Vector{Missing}, which a column set cannot hold,
# calls `f` on an empty vector when there are no groups, where it may throw, and keeps
# Vector{Any} where a column set must throw a ColumnTypeError.
normalize_missing_type(ref, other) = ref == "Missing" ? other : ref

is_frame(result) = result isa Tuple && first(result) === :frame
has_no_rows(result) = is_frame(result) && all(isempty, result[4])

function agree(reference, candidate)
    first(reference) === :error && has_no_rows(candidate) && return true
    if is_frame(reference) && "Any" in reference[3]
        return isequal(candidate, (:error, ColumnTypeError)) || (is_frame(candidate) && isequal(reference[4], candidate[4]))
    end
    is_frame(reference) && is_frame(candidate) || return isequal(reference, candidate)
    length(reference[3]) == length(candidate[3]) || return false
    types = map(normalize_missing_type, reference[3], candidate[3])
    return reference[2] == candidate[2] && types == candidate[3] && isequal(reference[4], candidate[4])
end

attempt(f, args...) = try
    canonical(Base.invokelatest(f, args...))
catch e
    (:error, typeof(e))
end

@testset "agreement with DataFrames on generated frames" begin
    @check max_examples = 1200 function grouped_operations(
        rows = ROWS,
        grouping = Data.SampledFrom(eachindex(GROUPINGS)),
        operation = Data.SampledFrom(eachindex(GROUP_FUNCTIONS)),
    )
        dfs, tfs = frame_of(DFSide, rows), frame_of(TFSide, rows)
        group_df, group_tf = GROUPINGS[grouping]
        op_df, op_tf = GROUP_FUNCTIONS[operation]
        reference = attempt(df -> op_df(df, Base.invokelatest(group_df, df)), dfs)
        candidate = attempt(df -> op_tf(df, Base.invokelatest(group_tf, df)), tfs)
        event!("grouping", GROUP_SETTINGS[grouping])
        event!("operation", GROUP_OPERATIONS[operation])
        event!("DataFrames", reference)
        event!("TrimmableFrames", candidate)
        agree(reference, candidate)
    end

    @check max_examples = 500 function frame_operations(
        rows = ROWS,
        operation = Data.SampledFrom(eachindex(FRAME_FUNCTIONS)),
    )
        dfs, tfs = frame_of(DFSide, rows), frame_of(TFSide, rows)
        op_df, op_tf = FRAME_FUNCTIONS[operation]
        reference = attempt(op_df, dfs)
        candidate = attempt(op_tf, tfs)
        event!("operation", FRAME_OPERATIONS[operation])
        event!("DataFrames", reference)
        event!("TrimmableFrames", candidate)
        agree(reference, candidate)
    end
end
