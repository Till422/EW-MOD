using JuMP # building models
using JuMP.Containers # use JuMP containers for parameters
using GLPK # solver for the JuMP model
using CSV # readin of CSV files
using DataFrames # data tables
using Statistics
using GLMakie


co_price = 75
interest_rate = 0.04
##################
### Data read in ###
##################
data_path = joinpath("data")
df_time = CSV.read(joinpath(data_path, "timedata.csv"), DataFrame)
df_tech = CSV.read(joinpath(data_path, "technology.csv"), DataFrame)

##################
### SETS ###
##################
T = collect(1:size(df_time, 1))
P = string.(df_tech.technology)
DISP = string.(df_tech[df_tech.dispatchable .== 1, "technology"])
NDISP = string.(df_tech[df_tech.dispatchable .== 0, "technology"])
S = string.(df_tech[df_tech.inv_storage .> 0, "technology"])

##################
### Parameters ###
##################
demand = DenseAxisArray(df_time.power, T)

#availability of pv and wind
df_avail = df_time[:,NDISP] # returns only the columns for pv and wind
avail = DenseAxisArray(Array(df_avail), T, NDISP) # creates an axisarray

mc = map(eachrow(filter(x-> x.dispatchable == 1, df_tech))) do row
    fc = row.fuel_cost
    ef = row.emission_factor
    eff = row.eff
    vc = row.variable_cost

    return fc/eff + co_price*ef/eff + vc
end

mc = DenseAxisArray(mc, DISP)

max_capacity = DenseAxisArray(df_tech.max_capacity, P)
eff = DenseAxisArray(df_tech.eff, P)
lost_load_cost = 1000

annuity(i,lifetime) = i * ((1 + i)^lifetime) / (((1 + i)^lifetime) - 1)
calc_inv_cost(oc, i, lt) = oc * annuity(i, lt)

invest_cost = map(
    row-> 1e3*calc_inv_cost(row.inv_power, interest_rate, row.lifetime),
    eachrow(df_tech)
)
invest_cost = DenseAxisArray(invest_cost, P)

invest_cost_storage = map(
    row-> 1e3*calc_inv_cost(row.inv_power, interest_rate, row.lifetime),
    eachrow(filter(x-> x.inv_storage > 0, df_tech))
)
invest_cost_storage = DenseAxisArray(invest_cost_storage, S)


m = Model(GLPK.Optimizer)
@variables m begin
    G[DISP, T] >= 0
    CU[T] >= 0
    CH[S, T] >= 0 # charging of storages
    L[S, T] >= 0 # storage level
    LL[T] >= 0 # infeasability variable: lost load

    POWER[P] >= 0
    STORAGE[S] >= 0
end

@expression(m, feedin[p=NDISP, t=T],
    POWER[p] * avail[t,p]
)

# the objective function vectorized
@objective(m, Min,
    8760/length(T) * (
        sum(mc[p] * G[p,t] for p in DISP , t in T)
        + sum(lost_load_cost * LL[t] for t in T)
    )
    + sum(invest_cost[p] * POWER[p] for p in P)
    + sum(invest_cost_storage[s] * STORAGE[s] for s in S)
)

# energy balance
@constraint(m,
    EnergyBalance[t=T],
    sum(G[p,t] for p in DISP)
    + sum(feedin[nd, t] for nd in NDISP)
    + LL[t]
    == 
    demand[t]
    + sum(CH[s,t] for s in S)
    + CU[t]
)

# max generation constraints
@constraint(m, MaxGeneration[p=DISP,t=T], G[p,t] <= POWER[p])
# max storages contrainst
@constraint(m, MaxCharge[s=S,t=T], CH[s,t] <= POWER[s])
@constraint(m, MaxStorage[s=S,t=T], L[s,t] <= STORAGE[s])

#define a function that gives us the next hour of the set T
next_hour(t) = t == T[end] ? T[1] : T[findfirst(isequal(t), T) + 1]
@constraint(m,StorageBalance[s=S, t=T],
    L[s,next_hour(t)]
    ==
    L[s,t]
    + eff[s] * CH[s,t]
    - G[s,t]/eff[s]
)


optimize!(m)

include(joinpath("functions", "plot.jl"))
plot_result()
