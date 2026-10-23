


use "$kill/data/CEMS_unit_characteristics22.dta", clear
keep PlantCode unitid maxgload Fuel Fuel2
rename PlantCode PLANT
rename Fuel fuelcems2
merge 1:m PLANT unitid using "$kill/data/emissions_electric_2022.dta", nogen keep (3)
collapse (sum) GLOAD SO2MASS NOXMASS CO2MASS (mean) maxgload, by(PLANT unitid Fuel2)
gen potential = maxgload * 8760
gen CF = GLOAD/potential
gen so2rate=SO2MASS/GLOAD
gen noxrate=NOXMASS/GLOAD
gen co2rate=CO2MASS/GLOAD
drop if Fuel2 == "Coal"
drop if Fuel2 == "Base"

sum CF if Fuel2=="Peak", d
sum CF if Fuel2=="CCGT", d

histogram CF if Fuel2=="Peak"
histogram CF if Fuel2=="CCGT"


pctile CFpeak = CF if Fuel2=="Peak", nq(20)

pctile CFcc= CF if Fuel2=="CCGT", nq(20)
*list CFcc in 1/10


pctile pctso2p = so2rate if Fuel=="Peak", nq(20)


pctile pctso2t = so2rate if Fuel=="CCGT", nq(20)


pctile pctnoxp = noxrate if Fuel=="Peak", nq(20)


pctile pctnoxt = noxrate if Fuel=="CCGT", nq(20)



pctile pctco2p = co2rate if Fuel =="Peak", nq(20)


pctile pctco2t = co2rate if Fuel =="CCGT", nq(20)



keep CFpeak CFcc pctso2p pctso2t pctnoxp pctnoxt pctco2p pctco2t

save "data/emission_rates_percentiles_CEMS.dta", replace
