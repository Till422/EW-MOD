using JuMP # building models
using JuMP.Containers # use JuMP containers for parameters
using GLPK # solver for the JuMP model
using CSV # readin of CSV files
using DataFrames # data tables
using Statistics
using GLMakie

#using CairoMakie
#using PlotlyJS

co_price = 300
interest_rate = 0.04
lost_load_cost = 100000
#lost_load_cost = 200
##################
### Data read in ###
##################



cd("C:\\Users\\Till\\Documents\\GitHub\\EW-MOD - Kopie")
working_directory = pwd()

data_path = joinpath("data_scen")
#df_time = CSV.read(joinpath(data_path, "data_bernau.csv"), DataFrame)
df_time = CSV.read(joinpath(data_path, "data_oneyear21.csv"), DataFrame)
df_tech = CSV.read(joinpath(data_path, "technology.csv"), DataFrame)


##################
### SETS ###
##################
T = unique(df_time.hour)
P = string.(df_tech.technology)
DISP = string.(df_tech[df_tech.dispatchable .== 1, "technology"])
NDISP = string.(df_tech[df_tech.dispatchable .== 0, "technology"])
S = string.(df_tech[df_tech.inv_storage .> 0, "technology"])

# SCEN_WEEK gibt die Zahlen 1-8 wieder (8 Szenarien)
SCEN_WEEK = unique(df_time.scenario)
# SCEN_PRICE gibt die Strings für 3 Preisszenarien wieder
SCEN_PRICE = ["low"]
#SCEN_PRICE = ["high"]
#SCEN_PRICE = ["average"]
#SCEN_PRICE = ["low", "average", "high"]
#SCEN gibt einen Vektor mit 24 Werten wieder (SCEN_WEEK, SCEN_PRICE )
SCEN = collect(Iterators.product(SCEN_WEEK, SCEN_PRICE))[:]

##################
### Parameters ###
##################

demand = DenseAxisArray{Float64}(undef, SCEN_WEEK, T)
avail = DenseAxisArray{Float64}(undef, SCEN_WEEK, T, NDISP)

#prices = DenseAxisArray([300, 500.0, 3000.0], SCEN_PRICE)    
prices = DenseAxisArray([300], SCEN_PRICE)  
#prices = DenseAxisArray([500], SCEN_PRICE) 
#prices = DenseAxisArray([3000], SCEN_PRICE) 

for row in eachrow(df_time)
    demand[row.scenario, row.hour] = row.load
    for ndisp in NDISP
        avail[row.scenario, row.hour, ndisp] = row[ndisp]
    end
end

mc = map(eachrow(filter(x-> x.dispatchable == 1, df_tech))) do row
    fc = row.fuel_cost
    ef = row.emission_factor
    eff = row.eff
    vc = row.variable_cost

    return fc/eff + co_price*ef/eff + vc
end

mc = DenseAxisArray(mc, DISP)

max_capacity = DenseAxisArray(df_tech.max_capacity, P)
fixed_capacity = DenseAxisArray(df_tech.fixed_capacity, P)
eff = DenseAxisArray(df_tech.eff, P)


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
    G[SCEN, DISP, T] >= 0
    CU[SCEN, T] >= 0
    CH[SCEN, S, T] >= 0 
    L[SCEN, S, T] >= 0 
    LL[SCEN, T] >= 0
    BUY[SCEN, T] >= 0
    POWER[P] >= 0
    STORAGE[S] >= 0
end

for p in P
    fixc = fixed_capacity[p]
    maxc = max_capacity[p]
    if (fixc >= 0) && (maxc >= fixc)
        JuMP.fix(POWER[p], fixed_capacity[p], force = true)
    elseif (maxc < fixc)
        @warn "Model will be infeasable. Fixed capacity of $p is higher than the maximum allowed capacity!"
    end
end

@expression(m, feedin[scen=SCEN, p=NDISP, t=T],
    POWER[p] * avail[scen[1],t,p] 
)


@objective(m, Min,
   8760/length(T) /length(SCEN) * (
      sum(mc[p] * G[scen, p,t] for scen in SCEN, p in DISP , t in T)
     + sum(lost_load_cost * LL[scen,t] for scen in SCEN, t in T)
    + sum(prices[scen[2]] * BUY[scen,t] for scen in SCEN, t in T)
)
+ sum(invest_cost[p] * POWER[p] for p in P)
+ sum(invest_cost_storage[s] * STORAGE[s] for s in S)   
)

@constraint(m,EnergyBalance[scen=SCEN, t=T],

    sum(G[scen, p,t] for p in DISP)
    + sum(feedin[scen, nd, t] for nd in NDISP)
    + LL[scen,t]
    + BUY[scen,t]GLP_ASN_MIN
    == 
    demand[scen[1], t]
    + sum(CH[scen, s,t] for s in S)
    + CU[scen,t]
)

@constraint(m, MaxGeneration[scen=SCEN, p=DISP,t=T], G[scen, p,t] <= POWER[p])

@constraint(m, MaxCharge[scen=SCEN, s=S,t=T], CH[scen, s,t] <= POWER[s])

@constraint(m, MaxStorage[scen=SCEN, s=S,t=T], L[scen, s,t] <= STORAGE[s])

@constraint(m, MaxInstalledCapacity[p=P], POWER[p] <= max_capacity[p])


next_hour(t) = t == T[end] ? T[1] : T[findfirst(isequal(t), T) + 1]

@constraint(m,StorageBalance[scen=SCEN, s=S, t=T],
    L[scen, s,next_hour(t)]
    ==
    L[scen,s,t]
    + eff[s] * CH[scen,s,t]
    - G[scen,s,t]/eff[s]
)


optimize!(m)
ov = objective_value(m)
include(joinpath("functions_scen", "plot_interactive.jl"))
fig = interactive_plot();

#Ausgabe:
ov
value.(m[:STORAGE])
power = value.(m[:POWER])
buy = value.(m[:BUY][SCEN,:])
sum(buy)
fig

