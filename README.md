#Energieversorgung einer wasserstoffbetriebenen Zugstrecke

Lineares Programm in Julia ([JuMP](https://jump.dev), GLPK) für die kostenminimale Kombination aus Photovoltaik, Windkraft, Batteriespeicher und Wasserstoffpfad zur Deckung des Fahrstroms einer Regionalbahnstrecke — gleichzeitig **Ausbau** und **Einsatz**: ein größerer Speicher erlaubt kleinere Erzeuger und umgekehrt. Wetterzeitreihen von [Renewables.ninja](https://www.renewables.ninja), **52,730 N / 13,008 O** — Basdorf bei Bernau an der Heidekrautbahn (MERRA-2, 2019, stündlich).

## Die beiden Modellvarianten

**`05-invest01.jl`** — deterministisch. Ein Szenario aus `data/` über 48 Stunden, erweiterter Technologiepark mit konventionellen Kraftwerken und CO₂-Preis 75 €/t.

**`strompreis_scen.jl`** — die eigentliche Untersuchung. Mehrere Wochenszenarien gemeinsam; `BUY` erlaubt Netzbezug, `SCEN_PRICE` schaltet zwischen `low`, `average`, `high` (300 / 500 / 3.000 €/MWh). Investition einmal für alle Szenarien, Einsatz je Szenario getrennt. CO₂-Preis 300 €/t, Zins 4 %, nicht gedeckte Last 100.000 €/MWh.

## Technologien

Im Szenariomodell (`data_scen/technology.csv`) nur emissionsfreie Optionen:

| Technologie | Wirkungsgrad | Investition Leistung | Investition Speicher | Lebensdauer |
|---|---|---|---|---|
| `pv` | — | 300 €/kW | — | 25 a |
| `wind` | — | 1.200 €/kW | — | 25 a |
| `battery` | 0,95 | 145 €/kW | 245 €/kWh | 12 a |
| `hydro` | 0,99 | 245 €/kW | 145 €/kWh | 20 a |

`hydro` bildet den Wasserstoffpfad ab — Umwandlung, Speicherung und Rückverstromung in einer Technologie, mit gegenüber der Batterie **umgekehrtem Kostenverhältnis**: teurer in der Leistung, günstiger im Volumen. Daher die Arbeitsteilung, die das Modell findet — Batterie für Tagesschwankungen, Wasserstoff für lange Schwachwindphasen. Investitionskosten annuitätisch auf ein Jahr umgelegt.

## Modellstruktur

Zielfunktion: annualisierte Investitionskosten plus hochskalierte Betriebskosten (Grenzkosten, nicht gedeckte Last, Netzbezug). Nebenbedingungen: `EnergyBalance` (Erzeugung + Zukauf + nicht gedeckte Last = Bedarf + Ladung + Abregelung), `MaxGeneration`, `MaxCharge`/`MaxStorage`, `MaxInstalledCapacity` als Grenzen für Erzeugung, Ladeleistung, Füllstand und Ausbau, dazu `StorageBalance`.

Die Speicherbilanz ist über `next_hour` **zyklisch**: Auf die letzte Stunde folgt wieder die erste — sonst ließe das Modell den Speicher kostenlos leerlaufen. `fixed_capacity` setzt Technologien auf eine feste Größe.

## Projektstruktur

```
├── 05-invest01.jl          Deterministisches Grundmodell
├── strompreis_scen.jl      Szenariomodell mit Netzbezug
├── Project.toml            Paketabhängigkeiten
├── data/                   Daten Grundmodell (technology.csv, timedata.csv)
├── data_scen/              Daten Szenariomodell
│   ├── technology*.csv     Parametervarianten (technology2: ohne Flächengrenze)
│   ├── data_bernau.csv     6 Wochenszenarien à 168 h
│   ├── data_oneyear21.csv  Volles Jahr, 8.760 h
│   └── ninja_*.csv         Rohdaten Renewables.ninja
├── functions/              Auswertung Grundmodell
├── functions_scen/         Interaktive Auswertung Szenariomodell
└── plots/                  Exportierte Ergebnisgrafiken
```

Zeitreihenspalten: `scenario`, `hour`, `pv`/`wind` als Verfügbarkeit (0–1), `load` als Fahrstrombedarf.

## Ausführen

Julia ab 1.6, im Projektordner:

```julia
using Pkg; Pkg.activate("."); Pkg.instantiate()
include("05-invest01.jl")
```

Ergebnisse: `objective_value(m)`, `value.(m[:POWER])`, `value.(m[:STORAGE])`, `sum(value.(m[:BUY]))`. Die Auswertung öffnet ein Fenster mit Schieberegler zwischen den Szenarien — braucht GLMakie und OpenGL, sonst `CairoMakie`.

