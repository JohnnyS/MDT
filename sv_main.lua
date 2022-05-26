-- (Start) Opening the MDT and sending data
AddEventHandler('erp_mdt:AddLog', function(text)
    exports.oxmysql:executeSync('INSERT INTO `pd_logs` (`text`, `time`) VALUES (@text, @time)', {
        ["@text"] = text,
        ["@time"] = os.time() * 1000
    })
end)

local function GetNameFromId(cid, cb)
    cb(exports.oxmysql:executeSync('SELECT firstname, lastname FROM `users` WHERE id =  @id LIMIT 1', {
        ["@id"] = cid
    }))
end

local function GetIdentifierFromCid(cid, cb)
    cb(exports.oxmysql:executeSync('SELECT identifier FROM `users` WHERE id =  @id LIMIT 1', {
        ["@id"] = cid
    }))
end

RegisterCommand("mdt", function(source, args, rawCommand)
    TriggerEvent('erp_mdt:open', source)
end, false)

--[[ESX.RegisterCommand({'mdt', 'openmdt'}, 'user', function(xPlayer, args, showError)
    local source = xPlayer.source
    TriggerEvent("erp_mdt:open", source)
end, false, {help = ('Police Mobile Data Terminal')})]]

RegisterNetEvent('erp_mdt:open')
AddEventHandler('erp_mdt:open', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance' or xPlayer.job.name == 'doj')) then
            TriggerClientEvent('erp_mdt:open', xPlayer.source, xPlayer.job.name, xPlayer.job.grade_label, xPlayer.variables.lastName, xPlayer.variables.firstName)
        end
    end
end)

function GetCallsign(cid)
    return exports.oxmysql:executeSync('SELECT callsign FROM `users` WHERE identifier = @id LIMIT 1', {["@id"] = cid})
end
exports('GetCallsign', GetCallsign) -- exports['erp_mdt']:GetCallsign(cid)


function GetDuty(cid)
    return exports.oxmysql:executeSync('SELECT duty FROM `users` WHERE identifier = @id LIMIT 1', {["@id"] = cid})
end
exports('GetDuty', GetDuty)

AddEventHandler('erp_mdt:open', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance')) then
            local cs = GetCallsign(xPlayer.getIdentifier())
                if cs then
                    TriggerClientEvent('erp_mdt:updateCallsign', xPlayer.source, cs[1].callsign)
                end
            local police, ems = {}, {}
            local players = ESX.GetExtendedPlayers()
            for k, v in pairs(players) do
			local callsign = GetCallsign(v.identifier)
			local onduty = GetDuty(v.identifier)
                if v.job.name == 'police' then
                    table.insert(police, {
                        cid = v.identifier,
                        name = v.name,
                        callsign = callsign[1].callsign,
                        duty = onduty[1].duty,
                    })
                elseif v.job.name == 'ambulance' then
                    table.insert(ems, {
                        cid = v.identifier,
                        name = v.name,
                        callsign = callsign[1].callsign,
                        duty = onduty[1].duty,
                    })
                end
            end
            TriggerClientEvent('erp_mdt:getActiveUnits', source, police, ems)
        end
    end
end)

local function GetIncidentName(id, cb)
    cb(exports.oxmysql:executeSync('SELECT title FROM `pd_incidents` WHERE id =  @id LIMIT 1', {
        ["@id"] = id
    }))
end

AddEventHandler('erp_mdt:open', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            -- get warrants
            exports.oxmysql:execute("SELECT * FROM pd_convictions WHERE warrant = '1'", {}, function(warrants)
                for i = 1, #warrants do
                    GetNameFromId(warrants[i]['cid'], function(res)
                        if res and res[1] then
                            warrants[i]['name'] = res[1]['firstname'] .. ' ' .. res[1]['lastname']
                        else
                            warrants[i]['name'] = "Unknown"
                        end
                    end)
                    GetIncidentName(warrants[i]['linkedincident'], function(res)
                        if res and res[1] then
                            warrants[i]['reporttitle'] = res[1]['title']
                        else
                            warrants[i]['reporttitle'] = "Unknown report title"
                        end
                    end)
                    warrants[i]['firsttime'] = i == 1
                    TriggerClientEvent('erp_mdt:dashboardWarrants', xPlayer.source, warrants[i])
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            exports.oxmysql:execute("SELECT * FROM `ems_reports` ORDER BY `id` DESC LIMIT 20", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
            end)
        end
    end
end)

AddEventHandler('erp_mdt:open', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        local calls = exports['erp_dispatch']:GetDispatchCalls()
        for id, information in pairs(calls) do
            if information['job'] then
                local found = false
                for i = 1, #information['job'] do
                    if information['job'][i] == xPlayer.job.name then
                        found = true
                        break
                    end
                end
                if not found then
                    calls[id] = nil
                end
            end
        end
        TriggerClientEvent('erp_mdt:dashboardCalls', xPlayer.source, calls)
    end
end)

-- (End) Opening the MDT and sending data

-- (Start) Requesting profile information

local function GetConvictions(cid, cb)
    cb((exports.oxmysql:executeSync('SELECT * FROM `pd_convictions` WHERE `cid` = @cid', {
        ["@cid"] = cid
    })))
end

local function GetLicenseInfo(cid, cb)
    cb(exports.oxmysql:executeSync('SELECT * FROM `user_licenses` WHERE `owner` = @cid', {
        ["@cid"] = cid
    }))
end

RegisterNetEvent('erp_mdt:searchProfile')
AddEventHandler('erp_mdt:searchProfile', function(sentData)
    if sentData then
        local function PpPpPpic(sex, profilepic)
            if profilepic then
                return profilepic
            end
            if sex == "f" then
                return "img/female.png"
            end
            return "img/male.png"
        end
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT id, identifier, firstname, lastname, sex, profilepic FROM `users` WHERE LOWER(`firstname`) LIKE @query OR LOWER(`lastname`) LIKE @query OR LOWER(`identifier`) LIKE @query OR CONCAT(LOWER(`firstname`), ' ', LOWER(`lastname`)) LIKE @query LIMIT 20",
                    {
                        ["@query"] = string.lower('%' .. sentData .. '%')
                    }, function(people)
                        for i = 1, #people do
                            
                            people[i]['warrant'] = false
                            people[i]['theory'] = false
                            people[i]['car'] = false
                            people[i]['bike'] = false
                            people[i]['truck'] = false

                            people[i]['weapon'] = false
                            people[i]['hunting'] = false
                            people[i]['fishing'] = false
                            people[i]['convictions'] = 0
                            people[i]['pp'] = PpPpPpic(people[i]['sex'], people[i]['profilepic'])

                            GetConvictions(people[i]['id'], function(cc)
                                if cc then
                                    for x = 1, #cc do
                                        if cc[x] then
                                            if cc[x]['warrant'] then
                                                people[i]['warrant'] = true
                                            end
                                            if cc[x]['associated'] == "0" then
                                                local charges = json.decode(cc[x]['charges'])
                                                people[i]['convictions'] = people[i]['convictions'] + #charges
                                            end
                                        end
                                    end
                                end
                            end)
                            GetLicenseInfo(people[i]['identifier'], function(licenseinfo)
                                if licenseinfo and #licenseinfo > 0 then
                                    for suckdick = 1, #licenseinfo do
                                        if licenseinfo[suckdick]['type'] == 'weapon' then
                                            people[i]['weapon'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'theory' then
                                            people[i]['theory'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive' then
                                            people[i]['car'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive_bike' then
                                            people[i]['bike'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive_truck' then
                                            people[i]['truck'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'hunting' then
                                            people[i]['hunting'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'fishing' then
                                            people[i]['fishing'] = true
                                        end
                                    end
                                end
                            end)
                        end

                        TriggerClientEvent('erp_mdt:searchProfile', xPlayer.source, people)
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute(
                    "SELECT id, identifier, firstname, lastname, sex, profilepic, dateofbirth FROM `users` WHERE LOWER(`firstname`) LIKE @query OR LOWER(`lastname`) LIKE @query OR LOWER(`identifier`) LIKE @query OR CONCAT(LOWER(`firstname`), ' ', LOWER(`lastname`)) LIKE @query LIMIT 20",
                    {
                        ["@query"] = string.lower('%' .. sentData .. '%')
                    }, function(people)
                        for i = 1, #people do
                            people[i]['warrant'] = false
                            people[i]['theory'] = false
                            people[i]['car'] = false
                            people[i]['bike'] = false
                            people[i]['truck'] = false
                            people[i]['weapon'] = false
                            people[i]['hunting'] = false
                            people[i]['fishing'] = false
                            people[i]['pp'] = PpPpPpic(people[i]['sex'], people[i]['profilepic'])
                            GetLicenseInfo(people[i]['identifier'], function(licenseinfo)
                                if licenseinfo and #licenseinfo > 0 then
                                    for suckdick = 1, #licenseinfo do
                                        if licenseinfo[suckdick]['type'] == 'weapon' then
                                            people[i]['weapon'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'theory' then
                                            people[i]['theory'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive' then
                                            people[i]['car'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive_bike' then
                                            people[i]['bike'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'drive_truck' then
                                            people[i]['truck'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'hunting' then
                                            people[i]['hunting'] = true
                                        elseif licenseinfo[suckdick]['type'] == 'fishing' then
                                            people[i]['fishing'] = true
                                        end
                                    end
                                end
                            end)
                        end

                        TriggerClientEvent('erp_mdt:searchProfile', xPlayer.source, people, true)
                    end)
            end
        end
    end
end)

-- (End) Requesting profile information

-- (Start) Bulletin

RegisterNetEvent('erp_mdt:opendashboard')
AddEventHandler('erp_mdt:opendashboard', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and xPlayer.job.name == 'police' then
            exports.oxmysql:execute('SELECT * FROM `pd_bulletin`', {}, function(bulletin)
                TriggerClientEvent('erp_mdt:dashboardbulletin', xPlayer.source, bulletin)
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            exports.oxmysql:execute('SELECT * FROM `ems_bulletin`', {}, function(bulletin)
                TriggerClientEvent('erp_mdt:dashboardbulletin', xPlayer.source, bulletin)
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'doj') then
            exports.oxmysql:execute('SELECT * FROM `doj_bulletin`', {}, function(bulletin)
                TriggerClientEvent('erp_mdt:dashboardbulletin', xPlayer.source, bulletin)
            end)
        end
    end
end)

RegisterNetEvent('erp_mdt:newBulletin')
AddEventHandler('erp_mdt:newBulletin', function(title, info, time)
    if title and info and time then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and xPlayer.job.name == 'police' then
                exports.oxmysql:insert(
                    'INSERT INTO `pd_bulletin` (`title`, `desc`, `author`, `time`) VALUES (@title, @desc, @author, @time)',
                    {
                        ["@title"] = title,
                        ["@desc"] = info,
                        ["@author"] = xPlayer.name,
                        ["@time"] = tostring(time)
                    }, function(sqlresult)
                        TriggerEvent('erp_mdt:AddLog', "A new bulletin was added by " .. xPlayer.variables.firstName .. " " ..
                            xPlayer.variables.lastName .. " with the title: " .. title .. "!")
                        TriggerClientEvent('erp_mdt:newBulletin', -1, xPlayer.source, {
                            id = sqlresult,
                            title = title,
                            info = info,
                            time = time,
                            author = xPlayer.name
                        }, 'police')
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:insert(
                    'INSERT INTO `ems_bulletin` (`title`, `desc`, `author`, `time`) VALUES (@title, @desc, @author, @time)',
                    {
                        ["@title"] = title,
                        ["@desc"] = info,
                        ["@author"] = xPlayer.name,
                        ["@time"] = tostring(time)
                    }, function(sqlresult)
                        TriggerEvent('erp_mdt:AddLog', "A new bulletin was added by " .. xPlayer.variables.firstName .. " " ..
                            xPlayer.variables.lastName .. " with the title: " .. title .. "!")
                        TriggerClientEvent('erp_mdt:newBulletin', -1, xPlayer.source, {
                            id = sqlresult,
                            title = title,
                            info = info,
                            time = time,
                            author = xPlayer.name
                        }, xPlayer.job.name)
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'doj') then
                exports.oxmysql:insert(
                    'INSERT INTO `doj_bulletin` (`title`, `desc`, `author`, `time`) VALUES (@title, @desc, @author, @time)',
                    {
                        ["@title"] = title,
                        ["@desc"] = info,
                        ["@author"] = xPlayer.name,
                        ["@time"] = tostring(time)
                    }, function(sqlresult)
                        TriggerEvent('erp_mdt:AddLog', "A new bulletin was added by " .. xPlayer.variables.firstName .. " " ..
                            xPlayer.variables.lastName .. " with the title: " .. title .. "!")
                        TriggerClientEvent('erp_mdt:newBulletin', -1, xPlayer.source, {
                            id = sqlresult,
                            title = title,
                            info = info,
                            time = time,
                            author = xPlayer.name
                        }, xPlayer.job.name)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:deleteBulletin')
AddEventHandler('erp_mdt:deleteBulletin', function(id)
    if id then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and xPlayer.job.name == 'police' then
                exports.oxmysql:execute('SELECT `title` FROM `pd_bulletin` WHERE id= @id LIMIT 1', {
                    ["@id"] = id
                }, function(res)
                    if res and res[1] then
                        exports.oxmysql:executeSync("DELETE FROM `pd_bulletin` WHERE id= @id", {
                            ["@id"] = id
                        })
                        TriggerEvent('erp_mdt:AddLog',
                            "A bulletin was deleted by " .. xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName ..
                                " with the title: " .. res[1]['title'] .. "!")
                        TriggerClientEvent('erp_mdt:deleteBulletin', -1, xPlayer.source, id, 'police')
                    end
                end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute('SELECT `title` FROM `ems_bulletin` WHERE id= @id LIMIT 1', {
                    ["@id"] = id
                }, function(res)
                    if res and res[1] then
                        exports.oxmysql:executeSync("DELETE FROM `ems_bulletin` WHERE id= @id", {
                            ["@id"] = id
                        })
                        TriggerEvent('erp_mdt:AddLog',
                            "A bulletin was deleted by " .. xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName ..
                                " with the title: " .. res[1]['title'] .. "!")
                        TriggerClientEvent('erp_mdt:deleteBulletin', -1, xPlayer.source, id, xPlayer.job.name)
                    end
                end)
            elseif xPlayer.job and (xPlayer.job.name == 'doj') then
                exports.oxmysql:execute('SELECT `title` FROM `doj_bulletin` WHERE id= @id LIMIT 1', {
                    ["@id"] = id
                }, function(res)
                    if res and res[1] then
                        exports.oxmysql:executeSync("DELETE FROM `doj_bulletin` WHERE id= @id", {
                            ["@id"] = id
                        })
                        TriggerEvent('erp_mdt:AddLog',
                            "A bulletin was deleted by " .. xPlayer.variables.firstName .. " " .. xPlayer.variables.lastName ..
                                " with the title: " .. res[1]['title'] .. "!")
                        TriggerClientEvent('erp_mdt:deleteBulletin', -1, xPlayer.source, id, xPlayer.job.name)
                    end
                end)
            end
        end
    end
end)

local function CreateUser(cid, dbname, cb)
    cb(exports.oxmysql:insert("INSERT INTO `" .. dbname .. "` (cid) VALUES (@cid)", {
        ["@cid"] = cid
    }))
    TriggerEvent('erp_mdt:AddLog', "A user was created with the CID: " .. cid)
end

local function GetPersonInformation(cid, table, cb)
    cb(exports.oxmysql:executeSync('SELECT information, tags, gallery FROM ' .. table .. ' WHERE cid = @cid', {
        ["@cid"] = cid
    }))
end

local function GetVehicleInformation(cid, cb)
    cb(exports.oxmysql:executeSync('SELECT owner, plate, vehicle FROM owned_vehicles WHERE owner = @cid', {
        ["@cid"] = cid
    }))
end

RegisterNetEvent('erp_mdt:getProfileData')
AddEventHandler('erp_mdt:getProfileData', function(sentId)
    local sentId = tonumber(sentId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            exports.oxmysql:execute(
                'SELECT id, identifier, firstname, lastname, job, profilepic, sex, dateofbirth FROM users WHERE id = @id LIMIT 1',
                {
                    ["@id"] = sentId
                }, function(user)
                    if user and user[1] then
                        --print(json.encode(user))
                        --print("1")
                        local function PpPpPpic(sex, profilepic)
                            if profilepic then
                                return profilepic
                            end
                            if sex == "f" then
                                return "img/female.png"
                            end
                            return "img/male.png"
                           
                        end
                        --print("2")
                        local object = {
                            cid = user[1]['id'],
							identifier = user[1]['identifier'],
                            firstname = user[1]['firstname'],
                            lastname = user[1]['lastname'],
                            job = user[1]['job'],
                            dateofbirth = user[1]['dateofbirth'],
                            profilepic = PpPpPpic(user[1]['sex'], user[1]['profilepic']),
                            policemdtinfo = '',
                            theory = false,
                            car = false,
                            bike = false,
                            truck = false,
                            weapon = false,
                            hunting = false,
                            fishing = false,
                            tags = {},
                            vehicles = {},
                            properties = {},
                            gallery = {},
                            convictions = {}
                        }
                        --print("3")
                        --print(object.identifier)
                        -- TriggerEvent('echorp:getJobInfo', object['job'], function(res)
                            -- if res then
                                -- object['job'] = res['label']
                            -- end
                        -- end)

                        GetConvictions(object['cid'], function(cc)
                            for x = 1, #cc do
                                if cc[x] then
                                    if cc[x]['associated'] == "0" then
                                        local charges = json.decode(cc[x]['charges'])
                                        for suckdick = 1, #charges do
                                            table.insert(object['convictions'], charges[suckdick])
                                        end
                                    end
                                end
                                --print("4")
                            end
                        end)

                        -- print(json.encode(object['convictions']))

                        GetPersonInformation(object['cid'], 'policemdtdata', function(information)
                            if information[1] then
                                object['policemdtinfo'] = information[1]['information']
                                object['tags'] = json.decode(information[1]['tags'])
                                object['gallery'] = json.decode(information[1]['gallery'])
                                --print("5")
                            end
                        end) -- Tags, Gallery, User Information

                        GetLicenseInfo(object['identifier'], function(licenseinfo)
                            if licenseinfo and #licenseinfo > 0 then
                                for suckdick = 1, #licenseinfo do
                                    if licenseinfo[suckdick]['type'] == 'weapon' then
                                        object['weapon'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'theory' then
                                        object['theory'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive' then
                                        object['car'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive_bike' then
                                        object['bike'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive_truck' then
                                        object['truck'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'hunting' then
                                        object['hunting'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'fishing' then
                                        object['fishing'] = true
                                    end
                                end
                                --print("6")
                            end
                        end) -- Licenses

                        GetVehicleInformation(object['identifier'], function(res)
                            local vehicleInfo = {}
                            for i = 1, #res do
                                local vehicle = json.decode(res[i]['vehicle'])
                                local model = "Unknown"
                                if json.encode(vehicle) ~= "null" then
                                    model = vehicle['model']
                                end
                                table.insert(vehicleInfo, {
                                    id = res[i]['id'],
                                    model = model,
                                    plate = res[i]['plate']
                                })
                            end
                            object['vehicles'] = vehicleInfo
                            --print("7")
                        end) -- Vehicles

                        -- local houses = exports['erp-housing']:GetHouses()
                        --print("7.5")
                        --local tPlayer = ESX.GetPlayerFromIdentifier(object.identifier)
                        --if tPlayer then
                            --local houses = exports.SSCompleteHousing:GetOwnedHouses(object)
                            --print(houses)
                            --print("8")
                            --local myHouses = {}
                            --print("8.5")
                            --[[for i=1, #houses do
                                print("9")
                                local thisHouse = houses[i]
                                print(thisHouse)
                                if thisHouse['cid'] == cid then
                                    print("10")
                                    table.insert(myHouses, thisHouse)
                                    print("House print")
                                end 
                            end]]
                            --object['properties'] = houses
                            --TriggerClientEvent('erp_mdt:getProfileData', xPlayer.source, object)
                        --end
                        TriggerClientEvent('erp_mdt:getProfileData', xPlayer.source, object)
                    end
                end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            exports.oxmysql:execute(
                'SELECT id, identifier, firstname, lastname, job, profilepic, sex, dateofbirth FROM users WHERE identifier = @id LIMIT 1',
                {
                    ["@id"] = sentId
                }, function(user)
                    if user and user[1] then

                        local function PpPpPpic(sex, profilepic)
                            if profilepic then
                                return profilepic
                            end
                            if sex == "f" then
                                return "img/female.png"
                            end
                            return "img/male.png"
                        end

                        local object = {
                            cid = user[1]['id'],
							identifier = user[1]['identifier'],
                            firstname = user[1]['firstname'],
                            lastname = user[1]['lastname'],
                            dateofbirth = user[1]['dateofbirth'],
                            job = user[1]['job'],
                            profilepic = PpPpPpic(user[1]['sex'], user[1]['profilepic']),
                            policemdtinfo = '',
                            theory = false,
                            car = false,
                            bike = false,
                            truck = false,
                            weapon = false,
                            hunting = false,
                            fishing = false,
                            tags = {},
                            properties = {},
                            gallery = {}
                        }

                        -- TriggerEvent('echorp:getJobInfo', object['job'], function(res)
                            -- if res then
                                -- object['job'] = res['label']
                            -- end
                        -- end)

                        GetPersonInformation(object['cid'], 'emsmdtdata', function(information)
                            if information[1] then
                                object['policemdtinfo'] = information[1]['information']
                                object['tags'] = json.decode(information[1]['tags'])
                                object['gallery'] = json.decode(information[1]['gallery'])
                            end
                        end) -- Tags, Gallery, User Information

                        GetLicenseInfo(object['identifier'], function(licenseinfo)
                            if licenseinfo and #licenseinfo > 0 then
                                for suckdick = 1, #licenseinfo do
                                    if licenseinfo[suckdick]['type'] == 'weapon' then
                                        object['weapon'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'theory' then
                                        object['theory'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive' then
                                        object['car'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive_bike' then
                                        object['bike'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'drive_truck' then
                                        object['truck'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'hunting' then
                                        object['hunting'] = true
                                    elseif licenseinfo[suckdick]['type'] == 'fishing' then
                                        object['fishing'] = true
                                    end
                                end
                            end
                        end) -- Licenses

                        TriggerClientEvent('erp_mdt:getProfileData', xPlayer.source, object, true)
                    end
                end)
        end
    end
end)

RegisterNetEvent("erp_mdt:saveProfile")
AddEventHandler('erp_mdt:saveProfile', function(pfp, information, cid, fName, sName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            local function UpdateInfo(id, pfp, desc)
                exports.oxmysql:executeSync(
                    "UPDATE policemdtdata SET `information` = @information WHERE `cid` = @id LIMIT 1", {
                        ["@id"] = cid,
                        ["@information"] = information
                    })
                exports.oxmysql:executeSync("UPDATE users SET `profilepic` = @profilepic WHERE `id`= @id LIMIT 1",
                    {
                        ["@id"] = cid,
                        ["@profilepic"] = pfp
                    })
                TriggerEvent('erp_mdt:AddLog',
                    "A user with the Citizen ID " .. cid .. " was updated by " .. xPlayer.name)

                if xPlayer.job.name == 'doj' then
                    exports.oxmysql:executeSync(
                        "UPDATE users SET `firstname` = @firstname, `lastname` = @lastname WHERE `identifier`= @id LIMIT 1",
                        {
                            ["@firstname"] = fName,
                            ["@lastname"] = sName,
                            ["@id"] = cid
                        })
                end
            end

            exports.oxmysql:execute('SELECT id FROM policemdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    UpdateInfo(user[1]['id'], pfp, information)
                else
                    CreateUser(cid, 'policemdtdata', function(xPlayer)
                        UpdateInfo(xPlayer, pfp, information)
                    end)
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            local function UpdateInfo(id, pfp, desc)
                exports.oxmysql:executeSync("UPDATE emsmdtdata SET `information` = @information WHERE `id` = @id LIMIT 1", {
                    ["@id"] = id,
                    ["@information"] = information
                })
                exports.oxmysql:executeSync("UPDATE users SET `profilepic`=:profilepic WHERE `identifier`= @id LIMIT 1",
                    {
                        id = cid,
                        profilepic = pfp
                    })
                TriggerEvent('erp_mdt:AddLog',
                    "A user with the Citizen ID " .. cid .. " was updated by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id FROM emsmdtdata WHERE cid=:cid LIMIT 1', {
                cid = cid
            }, function(user)
                if user and user[1] then
                    UpdateInfo(user[1]['id'], pfp, information)
                else
                    CreateUser(cid, 'emsmdtdata', function(xPlayer)
                        UpdateInfo(xPlayer, pfp, information)
                    end)
                end
            end)
        end
    end
end)

RegisterNetEvent("erp_mdt:newTag")
AddEventHandler('erp_mdt:newTag', function(cid, tag)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            local function UpdateTags(id, tags)
                exports.oxmysql:executeSync("UPDATE policemdtdata SET `tags` = @tags WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["tags"] = json.encode(tags)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " was added a new tag with the text (" .. tag .. ") by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, tags FROM policemdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local tags = json.decode(user[1]['tags'])
                    table.insert(tags, tag)
                    UpdateTags(user[1]['id'], tags)
                else
                    CreateUser(cid, 'policemdtdata', function(xPlayer)
                        local tags = {}
                        table.insert(tags, tag)
                        UpdateTags(xPlayer, tags)
                    end)
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            local function UpdateTags(id, tags)
                exports.oxmysql:executeSync("UPDATE emsmdtdata SET `tags` = @tags WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["tags"] = json.encode(tags)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " was added a new tag with the text (" .. tag .. ") by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, tags FROM emsmdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local tags = json.decode(user[1]['tags'])
                    table.insert(tags, tag)
                    UpdateTags(user[1]['id'], tags)
                else
                    CreateUser(cid, 'emsmdtdata', function(xPlayer)
                        local tags = {}
                        table.insert(tags, tag)
                        UpdateTags(xPlayer, tags)
                    end)
                end
            end)
        end
    end
end)

RegisterNetEvent("erp_mdt:removeProfileTag")
AddEventHandler('erp_mdt:removeProfileTag', function(cid, tagtext)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then

            local function UpdateTags(id, tag)
                exports.oxmysql:executeSync("UPDATE policemdtdata SET `tags` = @tags WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["@tags"] = json.encode(tag)
                })
                TriggerEvent('erp_mdt:AddLog',
                    "A user with the Citizen ID " .. id .. " was removed of a tag with the text (" .. tagtext .. ") by " ..
                        xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, tags FROM policemdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local tags = json.decode(user[1]['tags'])
                    for i = 1, #tags do
                        if tags[i] == tagtext then
                            table.remove(tags, i)
                        end
                    end
                    UpdateTags(user[1]['id'], tags)
                else
                    CreateUser(cid, 'policemdtdata', function(xPlayer)
                        UpdateTags(xPlayer, {})
                    end)
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then

            local function UpdateTags(id, tag)
                exports.oxmysql:executeSync("UPDATE emsmdtdata SET `tags` = @tags WHERE `id` = @id LIMIT 1", {
                    ["@id"] = id,
                    ["@tags"] = json.encode(tag)
                })
                TriggerEvent('erp_mdt:AddLog',
                    "A user with the Citizen ID " .. id .. " was removed of a tag with the text (" .. tagtext .. ") by " ..
                        xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, tags FROM emsmdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local tags = json.decode(user[1]['tags'])
                    for i = 1, #tags do
                        if tags[i] == tagtext then
                            table.remove(tags, i)
                        end
                    end
                    UpdateTags(user[1]['id'], tags)
                else
                    CreateUser(cid, 'emsmdtdata', function(xPlayer)
                        UpdateTags(xPlayer, {})
                    end)
                end
            end)
        end
    end
end)

RegisterNetEvent("erp_mdt:updateLicense")
AddEventHandler('erp_mdt:updateLicense', function(cid, type, status)
    local xPlayer = ESX.GetPlayerFromId(source)
    GetIdentifierFromCid(cid, function(res) licensecid = res[1].identifier	end)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' and xPlayer.job.grade ~= 0) then
            if status == 'give' then
                if xPlayer.job.grade >= 3 then
				    exports.oxmysql:executeSync('INSERT INTO user_licenses (type, owner) VALUES(@type, @owner)', {['@type'] = type, ['@owner'] = licensecid})
                else
                    TriggerClientEvent('t-notify:client:Custom', xPlayer.source, {
                        style  =  'error',
                        duration  =  5000,
                        message  =  'You are not authorized to give license, contact a higher up',
                        sound  =  true
                    })
                end
            elseif status == 'revoke' then
			    exports.oxmysql:executeSync('DELETE FROM user_licenses WHERE owner = @identifier AND type = @type', {['@identifier'] = licensecid, ['@type'] = type})
            end
        elseif xPlayer.job and (xPlayer.job.name == 'police' and xPlayer.job.grade == 0) then
            TriggerClientEvent('t-notify:client:Custom', xPlayer.source, {
                style  =  'error',
                duration  =  5000,
                message  =  'You are unable to perform this action due to your rank, contact a FTO',
                sound  =  true
            })
        elseif xPlayer.job and (xPlayer.job.name ~= 'police') then
            exports.JD_logs:createLog({
                EmbedMessage = "**MODDER** \n\n Job Locked Event Triggered when not the job",
                player_id = xPlayer.source,
                channel = "Security",
                screenshot = false
            })
            TriggerEvent("EasyAdmin:addBan", source, '[#JL-P] The pigs caught you oinking') 
        end
    end
end)

RegisterNetEvent("erp_mdt:addGalleryImg")
AddEventHandler('erp_mdt:addGalleryImg', function(cid, img)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then

            local function UpdateGallery(id, gallery)
                exports.oxmysql:executeSync("UPDATE policemdtdata SET `gallery` = :gallery WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["@gallery"] = json.encode(gallery)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " had their gallery updated (+) by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, gallery FROM policemdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local imgs = json.decode(user[1]['gallery'])
                    table.insert(imgs, img)
                    UpdateGallery(user[1]['id'], imgs)
                else
                    CreateUser(cid, 'policemdtdata', function(xPlayer)
                        local imgs = {}
                        table.insert(imgs, img)
                        UpdateGallery(xPlayer, imgs)
                    end)
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then

            local function UpdateGallery(id, gallery)
                exports.oxmysql:executeSync("UPDATE emsmdtdata SET `gallery`= @gallery WHERE `id` = @id LIMIT 1", {
                    ["@cid"] = id,
                    ["@gallery"] = json.encode(gallery)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " had their gallery updated (+) by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, gallery FROM emsmdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local imgs = json.decode(user[1]['gallery'])
                    table.insert(imgs, img)
                    UpdateGallery(user[1]['id'], imgs)
                else
                    CreateUser(cid, 'emsmdtdata', function(xPlayer)
                        local imgs = {}
                        table.insert(imgs, img)
                        UpdateGallery(xPlayer, imgs)
                    end)
                end
            end)
        end
    end
end)

RegisterNetEvent("erp_mdt:removeGalleryImg")
AddEventHandler('erp_mdt:removeGalleryImg', function(cid, img)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then

            local function UpdateGallery(id, gallery)
                exports.oxmysql:executeSync("UPDATE policemdtdata SET `gallery` = @gallery WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["@gallery"] = json.encode(gallery)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " had their gallery updated (-) by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, gallery FROM policemdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local imgs = json.decode(user[1]['gallery'])
                    -- table.insert(imgs, img)
                    for i = 1, #imgs do
                        if imgs[i] == img then
                            table.remove(imgs, i)
                        end
                    end

                    UpdateGallery(user[1]['id'], imgs)
                else
                    CreateUser(cid, 'policemdtdata', function(xPlayer)
                        local imgs = {}
                        UpdateGallery(xPlayer, imgs)
                    end)
                end
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then

            local function UpdateGallery(id, gallery)
                exports.oxmysql:executeSync("UPDATE emsmdtdata SET `gallery` = @gallery WHERE `id`= @id LIMIT 1", {
                    ["@id"] = id,
                    ["@gallery"] = json.encode(gallery)
                })
                TriggerEvent('erp_mdt:AddLog', "A user with the Citizen ID " .. id ..
                    " had their gallery updated (-) by " .. xPlayer.name)
            end

            exports.oxmysql:execute('SELECT id, gallery FROM emsmdtdata WHERE cid = @cid LIMIT 1', {
                ["@cid"] = cid
            }, function(user)
                if user and user[1] then
                    local imgs = json.decode(user[1]['gallery'])
                    -- table.insert(imgs, img)
                    for i = 1, #imgs do
                        if imgs[i] == img then
                            table.remove(imgs, i)
                        end
                    end

                    UpdateGallery(user[1]['id'], imgs)
                else
                    CreateUser(cid, 'emsmdtdata', function(xPlayer)
                        local imgs = {}
                        UpdateGallery(xPlayer, imgs)
                    end)
                end
            end)
        end
    end
end)

-- Incidents

RegisterNetEvent('erp_mdt:getAllIncidents')
AddEventHandler('erp_mdt:getAllIncidents', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            exports.oxmysql:execute("SELECT * FROM `pd_incidents` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllIncidents', xPlayer.source, matches)
            end)
        end
    end
end)

RegisterNetEvent('erp_mdt:searchIncidents')
AddEventHandler('erp_mdt:searchIncidents', function(query)
    if query then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT * FROM `pd_incidents` WHERE `id` LIKE @query OR LOWER(`title`) LIKE @query OR LOWER(`author`) LIKE @query OR LOWER(`details`) LIKE @query OR LOWER(`tags`) LIKE @query OR LOWER(`officersinvolved`) LIKE @query OR LOWER(`civsinvolved`) LIKE @query OR LOWER(`author`) LIKE @query ORDER BY `id` DESC LIMIT 50",
                    {
                        ["@query"] = string.lower('%' .. query .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getIncidents', xPlayer.source, matches)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:getIncidentData')
AddEventHandler('erp_mdt:getIncidentData', function(sentId)
    if sentId then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute("SELECT * FROM `pd_incidents` WHERE `id` = @id", {
                    ["@id"] = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['civsinvolved'] = json.decode(data['civsinvolved'])
                    data['evidence'] = json.decode(data['evidence'])
                    exports.oxmysql:execute("SELECT * FROM `pd_incidents` WHERE `id` =  @id", {
                        ["@id"] = sentId
                    }, function(matches)
                        exports.oxmysql:execute("SELECT * FROM `pd_convictions` WHERE `linkedincident` =  @id", {
                            ["@id"] = sentId
                        }, function(convictions)
                            for i = 1, #convictions do
                                GetNameFromId(convictions[i]['cid'], function(res)
                                    if res and res[1] then
                                        convictions[i]['name'] = res[1]['firstname'] .. ' ' .. res[1]['lastname']
                                    else
                                        convictions[i]['name'] = "Unknown"
                                    end
                                end)
                                convictions[i]['charges'] = json.decode(convictions[i]['charges'])
                            end
                            TriggerClientEvent('erp_mdt:getIncidentData', xPlayer.source, data, convictions)
                        end)
                    end)
                end)
            end
        end
    end
end)

local debug = false

if debug then
    CreateThread(function()
        local data = {
            [1] = {
                cid = 1990,
                name = "Flakey"
            },
            [2] = {
                cid = 1523,
                name = "Test User"
            }
        }
        print(json.encode(data))
    end)
end

RegisterNetEvent('erp_mdt:getAllBolos')
AddEventHandler('erp_mdt:getAllBolos', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
            exports.oxmysql:execute("SELECT * FROM `pd_bolos`", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllBolos', xPlayer.source, matches)
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            exports.oxmysql:execute("SELECT * FROM `ems_icu`", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllBolos', xPlayer.source, matches)
            end)
        end
    end
end)

RegisterNetEvent('erp_mdt:searchBolos')
AddEventHandler('erp_mdt:searchBolos', function(sentSearch)
    if sentSearch then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT * FROM `pd_bolos` WHERE `id` LIKE @query OR LOWER(`title`) LIKE @query OR `plate` LIKE @query OR LOWER(`owner`) LIKE @query OR LOWER(`individual`) LIKE @query OR LOWER(`detail`) LIKE @query OR LOWER(`officersinvolved`) LIKE @query OR LOWER(`tags`) LIKE @query OR LOWER(`author`) LIKE @query",
                    {
                        ["@query"] = string.lower('%' .. sentSearch .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getBolos', xPlayer.source, matches)
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute(
                    "SELECT * FROM `ems_icu` WHERE `id` LIKE @query OR LOWER(`title`) LIKE @query OR `plate` LIKE @query OR LOWER(`owner`) LIKE @query OR LOWER(`individual`) LIKE @query OR LOWER(`detail`) LIKE @query OR LOWER(`officersinvolved`) LIKE @query OR LOWER(`tags`) LIKE @query OR LOWER(`author`) LIKE @query",
                    {
                        ["@query"] = string.lower('%' .. sentSearch .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getBolos', xPlayer.source, matches)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:getBoloData')
AddEventHandler('erp_mdt:getBoloData', function(sentId)
    if sentId then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute("SELECT * FROM `pd_bolos` WHERE `id` =  @id LIMIT 1", {
                    ["@id"] = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['gallery'] = json.decode(data['gallery'])
                    TriggerClientEvent('erp_mdt:getBoloData', xPlayer.source, data)
                end)

            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute("SELECT * FROM `ems_icu` WHERE `id` =  @id LIMIT 1", {
                    ["@id"] = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['gallery'] = json.decode(data['gallery'])
                    TriggerClientEvent('erp_mdt:getBoloData', xPlayer.source, data)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:newBolo')
AddEventHandler('erp_mdt:newBolo', function(existing, id, title, plate, owner, individual, detail, tags, gallery, officersinvolved, time)
    if id then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then

                local function InsertBolo()
                    exports.oxmysql:insert(
                        'INSERT INTO `pd_bolos` (`title`, `author`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officersinvolved`, `time`) VALUES (@title, @author, @plate, @owner, @individual, @detail, @tags, @gallery, @officersinvolved, @time)',
                        {
                            ["@title"] = title,
                            ["@author"] = xPlayer.name,
                            ["@plate"] = plate,
                            ["@owner"] = owner,
                            ["@individual"] = individual,
                            ["@detail"] = detail,
                            ["@tags"] = json.encode(tags),
                            ["@gallery"] = json.encode(gallery),
                            ["@officersinvolved"] = json.encode(officersinvolved),
                            ["@time"] = tostring(time)
                        }, function(r)
                            if r then
                                TriggerClientEvent('erp_mdt:boloComplete', xPlayer.source, r)
                                TriggerEvent('erp_mdt:AddLog', "A new BOLO was created by " .. xPlayer.name ..
                                    " with the title (" .. title .. ") and ID (" .. id .. ")")
                            end
                        end)
                end

                local function UpdateBolo()
                    exports.oxmysql:update(
                        "UPDATE pd_bolos SET `title`=:title, plate=:plate, owner=:owner, individual=:individual, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved WHERE `id`= @id LIMIT 1",
                        {
                            ["@title"] = title,
                            ["@plate"] = plate,
                            ["@owner"] = owner,
                            ["@individual"] = individual,
                            ["@detail"] = detail,
                            ["@tags"] = json.encode(tags),
                            ["@gallery"] = json.encode(gallery),
                            ["@officersinvolved"] = json.encode(officersinvolved),
                            ["@id"] = id
                        }, function(r)
                            if r then
                                TriggerClientEvent('erp_mdt:boloComplete', xPlayer.source, id)
                                TriggerEvent('erp_mdt:AddLog', "A BOLO was updated by " .. xPlayer.name ..
                                    " with the title (" .. title .. ") and ID (" .. id .. ")")
                            end
                        end)
                end

                if existing then
                    UpdateBolo()
                elseif not existing then
                    InsertBolo()
                end
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then

                local function InsertBolo()
                    exports.oxmysql:insert(
                        'INSERT INTO `ems_icu` (`title`, `author`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officersinvolved`, `time`) VALUES (:title, :author, :plate, :owner, :individual, :detail, :tags, :gallery, :officersinvolved, :time)',
                        {
                            title = title,
                            author = xPlayer.name,
                            plate = plate,
                            owner = owner,
                            individual = individual,
                            detail = detail,
                            tags = json.encode(tags),
                            gallery = json.encode(gallery),
                            officersinvolved = json.encode(officersinvolved),
                            time = tostring(time)
                        }, function(r)
                            if r then
                                TriggerClientEvent('erp_mdt:boloComplete', xPlayer.source, r)
                                TriggerEvent('erp_mdt:AddLog',
                                    "A new ICU Check-in was created by " .. xPlayer.name .. " with the title (" ..
                                        title .. ") and ID (" .. id .. ")")
                            end
                        end)
                end

                local function UpdateBolo()
                    exports.oxmysql:update(
                        "UPDATE `ems_icu` SET `title`=:title, plate=:plate, owner=:owner, individual=:individual, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved WHERE `id`= @id LIMIT 1",
                        {
                            title = title,
                            plate = plate,
                            owner = owner,
                            individual = individual,
                            detail = detail,
                            tags = json.encode(tags),
                            gallery = json.encode(gallery),
                            officersinvolved = json.encode(officersinvolved),
                            id = id
                        }, function(affectedRows)
                            if affectedRows > 0 then
                                TriggerClientEvent('erp_mdt:boloComplete', xPlayer.source, id)
                                TriggerEvent('erp_mdt:AddLog',
                                    "A ICU Check-in was updated by " .. xPlayer.name .. " with the title (" ..
                                        title .. ") and ID (" .. id .. ")")
                            end
                        end)
                end

                if existing then
                    UpdateBolo()
                elseif not existing then
                    InsertBolo()
                end
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:deleteBolo')
AddEventHandler('erp_mdt:deleteBolo', function(id)
    if id then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:executeSync("DELETE FROM `pd_bolos` WHERE id= @id", {
                    id = id
                })
                TriggerEvent('erp_mdt:AddLog',
                    "A BOLO was deleted by " .. xPlayer.name .. " with the ID (" .. id .. ")")
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:deleteICU')
AddEventHandler('erp_mdt:deleteICU', function(id)
    if id then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:executeSync("DELETE FROM `ems_icu` WHERE id= @id", {
                    id = id
                })
                TriggerEvent('erp_mdt:AddLog',
                    "A ICU Check-in was deleted by " .. xPlayer.name .. " with the ID (" .. id .. ")")
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:incidentSearchPerson')
AddEventHandler('erp_mdt:incidentSearchPerson', function(name)
    if name then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then

                local function PpPpPpic(sex, profilepic)
                    if profilepic then
                        return profilepic
                    end
                    if sex == "f" then
                        return "img/female.png"
                    end
                    return "img/male.png"
                end

                exports.oxmysql:execute(
                    "SELECT id, identifier, firstname, lastname, profilepic, sex FROM `users` WHERE LOWER(`firstname`) LIKE @query OR LOWER(`lastname`) LIKE @query OR LOWER(`identifier`) LIKE @query OR CONCAT(LOWER(`firstname`), ' ', LOWER(`lastname`)) LIKE @query LIMIT 30",
                    {
                        ["@query"] = string.lower('%' .. name .. '%') -- % wildcard, needed to search for all alike results
                    }, function(data)
                        for i = 1, #data do
                            data[i]['profilepic'] = PpPpPpic(data[i]['sex'], data[i]['profilepic'])
                        end
                        TriggerClientEvent('erp_mdt:incidentSearchPerson', xPlayer.source, data)
                    end)
            end
        end
    end
end)

-- Reports

RegisterNetEvent('erp_mdt:getAllReports')
AddEventHandler('erp_mdt:getAllReports', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police') then
            exports.oxmysql:execute("SELECT * FROM `pd_reports` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
            exports.oxmysql:execute("SELECT * FROM `ems_reports` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
            end)
        elseif xPlayer.job and (xPlayer.job.name == 'doj') then
            exports.oxmysql:execute("SELECT * FROM `doj_reports` ORDER BY `id` DESC LIMIT 30", {}, function(matches)
                TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
            end)
        end
    end
end)

RegisterNetEvent('erp_mdt:getReportData')
AddEventHandler('erp_mdt:getReportData', function(sentId)
    if sentId then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and xPlayer.job.name == 'police' then
                exports.oxmysql:execute("SELECT * FROM `pd_reports` WHERE `id` =  @id LIMIT 1", {
                    id = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['civsinvolved'] = json.decode(data['civsinvolved'])
                    data['gallery'] = json.decode(data['gallery'])
                    TriggerClientEvent('erp_mdt:getReportData', xPlayer.source, data)
                end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute("SELECT * FROM `ems_reports` WHERE `id` =  @id LIMIT 1", {
                    id = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['civsinvolved'] = json.decode(data['civsinvolved'])
                    data['gallery'] = json.decode(data['gallery'])
                    TriggerClientEvent('erp_mdt:getReportData', xPlayer.source, data)
                end)
            elseif xPlayer.job and (xPlayer.job.name == 'doj') then
                exports.oxmysql:execute("SELECT * FROM `doj_reports` WHERE `id` =  @id LIMIT 1", {
                    id = sentId
                }, function(matches)
                    local data = matches[1]
                    data['tags'] = json.decode(data['tags'])
                    data['officersinvolved'] = json.decode(data['officersinvolved'])
                    data['civsinvolved'] = json.decode(data['civsinvolved'])
                    data['gallery'] = json.decode(data['gallery'])
                    TriggerClientEvent('erp_mdt:getReportData', xPlayer.source, data)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:searchReports')
AddEventHandler('erp_mdt:searchReports', function(sentSearch)
    if sentSearch then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and xPlayer.job.name == 'police' then
                exports.oxmysql:execute(
                    "SELECT * FROM `pd_reports` WHERE `id` LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`type`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`tags`) LIKE :query ORDER BY `id` DESC LIMIT 50",
                    {
                        query = string.lower('%' .. sentSearch .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then
                exports.oxmysql:execute(
                    "SELECT * FROM `ems_reports` WHERE `id` LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`type`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`tags`) LIKE :query ORDER BY `id` DESC LIMIT 50",
                    {
                        query = string.lower('%' .. sentSearch .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
                    end)
            elseif xPlayer.job and (xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT * FROM `doj_reports` WHERE `id` LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`type`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`tags`) LIKE :query ORDER BY `id` DESC LIMIT 50",
                    {
                        query = string.lower('%' .. sentSearch .. '%') -- % wildcard, needed to search for all alike results
                    }, function(matches)
                        TriggerClientEvent('erp_mdt:getAllReports', xPlayer.source, matches)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:newReport')
AddEventHandler('erp_mdt:newReport', function(existing, id, title, reporttype, detail, tags, gallery, officers, civilians, time)
        if id then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer then
                if xPlayer.job and xPlayer.job.name == 'police' then

                    local function InsertBolo()
                        exports.oxmysql:insert(
                            'INSERT INTO `pd_reports` (`title`, `author`, `type`, `detail`, `tags`, `gallery`, `officersinvolved`, `civsinvolved`, `time`) VALUES (:title, :author, :type, :detail, :tags, :gallery, :officersinvolved, :civsinvolved, :time)',
                            {
                                title = title,
                                author = xPlayer.name,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                time = tostring(time)
                            }, function(r)
                                if r then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, r)
                                    TriggerEvent('erp_mdt:AddLog', "A new report was created by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    local function UpdateBolo()
                        exports.oxmysql:update(
                            "UPDATE `pd_reports` SET `title`=:title, type=:type, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved, civsinvolved=:civsinvolved WHERE `id`= @id LIMIT 1",
                            {
                                title = title,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                id = id
                            }, function(affectedRows)
                                if affectedRows > 0 then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, id)
                                    TriggerEvent('erp_mdt:AddLog', "A report was updated by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    if existing then
                        UpdateBolo()
                    elseif not existing then
                        InsertBolo()
                    end
                elseif xPlayer.job and (xPlayer.job.name == 'ambulance') then

                    local function InsertBolo()
                        exports.oxmysql:insert(
                            'INSERT INTO `ems_reports` (`title`, `author`, `type`, `detail`, `tags`, `gallery`, `officersinvolved`, `civsinvolved`, `time`) VALUES (:title, :author, :type, :detail, :tags, :gallery, :officersinvolved, :civsinvolved, :time)',
                            {
                                title = title,
                                author = xPlayer.name,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                time = tostring(time)
                            }, function(r)
                                if r > 0 then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, r)
                                    TriggerEvent('erp_mdt:AddLog', "A new report was created by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    local function UpdateBolo()
                        exports.oxmysql:update(
                            "UPDATE `ems_reports` SET `title`=:title, type=:type, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved, civsinvolved=:civsinvolved WHERE `id`= @id LIMIT 1",
                            {
                                title = title,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                id = id
                            }, function(r)
                                if r > 0 then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, id)
                                    TriggerEvent('erp_mdt:AddLog', "A report was updated by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    if existing then
                        UpdateBolo()
                    elseif not existing then
                        InsertBolo()
                    end
                elseif xPlayer.job and (xPlayer.job.name == 'doj') then

                    local function InsertBolo()
                        exports.oxmysql:insert(
                            'INSERT INTO `doj_reports` (`title`, `author`, `type`, `detail`, `tags`, `gallery`, `officersinvolved`, `civsinvolved`, `time`) VALUES (:title, :author, :type, :detail, :tags, :gallery, :officersinvolved, :civsinvolved, :time)',
                            {
                                title = title,
                                author = xPlayer.name,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                time = tostring(time)
                            }, function(r)
                                if r > 0 then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, r)
                                    TriggerEvent('erp_mdt:AddLog', "A new report was created by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    local function UpdateBolo()
                        exports.oxmysql:update(
                            "UPDATE `doj_reports` SET `title`=:title, type=:type, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved, civsinvolved=:civsinvolved WHERE `id`= @id LIMIT 1",
                            {
                                title = title,
                                type = reporttype,
                                detail = detail,
                                tags = json.encode(tags),
                                gallery = json.encode(gallery),
                                officersinvolved = json.encode(officers),
                                civsinvolved = json.encode(civilians),
                                id = id
                            }, function(r)
                                if r > 0 then
                                    TriggerClientEvent('erp_mdt:reportComplete', xPlayer.source, id)
                                    TriggerEvent('erp_mdt:AddLog', "A report was updated by " .. xPlayer.name ..
                                        " with the title (" .. title .. ") and ID (" .. id .. ")")
                                end
                            end)
                    end

                    if existing then
                        UpdateBolo()
                    elseif not existing then
                        InsertBolo()
                    end
                end
            end
        end
    end)

-- DMV

--[[local function GetImpoundStatus(vehicleid, cb)
    cb(#(exports.oxmysql:executeSync('SELECT id FROM `impound` WHERE `vehicleid` = @vehicleid', {['@vehicleid'] = vehicleid})) > 0)
end]]

local function GetBoloStatus(plate, cb)
    cb(exports.oxmysql:executeSync('SELECT id FROM `pd_bolos` WHERE LOWER (`plate`) = @plate', {
        ["@plate"] = string.lower(plate)
    }))
end

local function GetOwnerName(cid, cb)
    cb(exports.oxmysql:executeSync('SELECT firstname, lastname FROM `users` WHERE identifier = @cid LIMIT 1', {
        ["@cid"] = cid
    }))
end

local function GetVehicleInformation(plate, cb)
    cb(exports.oxmysql:executeSync('SELECT id, information FROM `pd_vehicleinfo` WHERE plate = @plate', {
        ["@plate"] = plate
    }))
end

RegisterNetEvent('erp_mdt:searchVehicles')
AddEventHandler('erp_mdt:searchVehicles', function(search, hash)
    if search then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT owner, plate, vehicle, image FROM `owned_vehicles` WHERE LOWER(`plate`) LIKE @query OR LOWER(`vehicle`) LIKE @hash LIMIT 25",
                    {
                        ["@query"] = string.lower('%' .. search .. '%'),
                        ["@hash"] = string.lower('%' .. hash .. '%')
                    }, function(vehicles)
                        for i = 1, #vehicles do

                            -- Impound Status
                            -- GetImpoundStatus(vehicles[i]['plate'], function(impoundStatus)
                                -- vehicles[i]['impound'] = impoundStatus
                            -- end)
                            --vehicles[i]['impound'] = false
                            vehicles[i]['bolo'] = false


                            -- Bolo Status
                            GetBoloStatus(vehicles[i]['plate'], function(boloStatus)
                                if boloStatus and boloStatus[1] then
                                    vehicles[i]['bolo'] = true
                                end
                            end)

                            GetOwnerName(vehicles[i]['owner'], function(name)
                                if name and name[1] then
                                    vehicles[i]['owner'] = name[1]['firstname'] .. ' ' .. name[1]['lastname']
                                end
                            end)

                             if vehicles[i]['image'] == nil then
                                 vehicles[i]['image'] = "img/not-found.jpg"
                             end

                        end

                        TriggerClientEvent('erp_mdt:searchVehicles', xPlayer.source, vehicles)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:getVehicleData')
AddEventHandler('erp_mdt:getVehicleData', function(plate)
    if plate then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                exports.oxmysql:execute(
                    "SELECT owner, plate, vehicle, image FROM `owned_vehicles` WHERE plate = @plate LIMIT 1",
                    {
                        ["@plate"] = string.gsub(plate, "^%s*(.-)%s*$", "%1")
                    }, function(vehicle)
                        if vehicle and vehicle[1] then
						    local vehData = json.decode(vehicle[1].vehicle)
							--print(vehData.model)
                            --vehicle[1]['impound'] = false
                            -- GetImpoundStatus(vehicle[1]['plate'], function(impoundStatus)
                                -- vehicle[1]['impound'] = impoundStatus
                            -- end)

                            vehicle[1]['bolo'] = false
                            vehicle[1]['information'] = ""

                            
                            -- Bolo Status
                            GetBoloStatus(vehicle[1]['plate'], function(boloStatus)
                                if boloStatus and boloStatus[1] then
                                    vehicle[1]['bolo'] = true
                                end
                            end) -- Used to get BOLO status.

                            vehicle[1]['name'] = "Unknown Person"

                            GetOwnerName(vehicle[1]['owner'], function(name)
                                if name and name[1] then
                                    vehicle[1]['name'] = name[1]['firstname'] .. ' ' .. name[1]['lastname']
                                end
                            end) -- Get's vehicle owner name name.

                            vehicle[1]['dbid'] = 0

                            GetVehicleInformation(vehicle[1]['plate'], function(info)
                                if info and info[1] then
                                    vehicle[1]['information'] = info[1]['information']
                                    vehicle[1]['dbid'] = info[1]['plate']
                                end
                            end) -- Vehicle notes and database ID if there is one.
                            --print(GetLabelText(GetDisplayNameFromVehicleModel(vehData.model)))
                            -- if vehicle[1]['image'] == nil then
                                -- vehicle[1]['image'] = "img/" .. GetLabelText(GetDisplayNameFromVehicleModel(vehData.model)) .. ".jpg"
                            -- end -- Image
                        end
                        TriggerClientEvent('erp_mdt:getVehicleData', xPlayer.source, vehicle)
                    end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:saveVehicleInfo')
AddEventHandler('erp_mdt:saveVehicleInfo', function(dbid, plate, imageurl, notes)
    if plate then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.job and (xPlayer.job.name == 'police' or xPlayer.job.name == 'doj') then
                if dbid == nil then
                    dbid = 0
                end
                exports.oxmysql:executeSync("UPDATE owned_vehicles SET `image` = @image WHERE `plate` = @plate LIMIT 1", {
                    ["@plate"] = string.gsub(plate, "^%s*(.-)%s*$", "%1"),
                    ["@image"] = imageurl
                })
                TriggerEvent('erp_mdt:AddLog', "A vehicle with the plate (" .. plate .. ") has a new image (" ..
                    imageurl .. ") edited by " .. xPlayer.name)
                if tonumber(dbid) == 0 then
                    exports.oxmysql:insert(
                        'INSERT INTO `pd_vehicleinfo` (`plate`, `information`) VALUES (@plate, @information)', {
                            ["@plate"] = string.gsub(plate, "^%s*(.-)%s*$", "%1"),
                            ["@information"] = notes
                        }, function(infoResult)
                            if infoResult then
                                TriggerClientEvent('erp_mdt:updateVehicleDbId', xPlayer.source, infoResult)
                                TriggerEvent('erp_mdt:AddLog', "A vehicle with the plate (" .. plate ..
                                    ") was added to the vehicle information database by " .. xPlayer.name)
                            end
                        end)
                elseif tonumber(dbid) > 0 then
                    exports.oxmysql:executeSync(
                        "UPDATE pd_vehicleinfo SET `information` = @information WHERE `plate` = @plate LIMIT 1", {
                            ["@plate"] = string.gsub(plate, "^%s*(.-)%s*$", "%1"),
                            ["@information"] = notes
                        })
                end
            end
        end
    end
end)

local LogPerms = {
    ['ambulance'] = {
	    [4] = true,
        [5] = true,
    },
    ['police'] = {
        [5] = true,
        [6] = true,
        [7] = true
    },
}

RegisterNetEvent('erp_mdt:getAllLogs')
AddEventHandler('erp_mdt:getAllLogs', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if LogPerms[xPlayer.job.name][xPlayer.job.grade] then
            exports.oxmysql:execute('SELECT * FROM pd_logs ORDER BY `id` DESC LIMIT 250', {}, function(infoResult)
                TriggerLatentClientEvent('erp_mdt:getAllLogs', xPlayer.source, 30000, infoResult)
            end)
        end
    end
end)

--Penal Code
local PenalCodeTitles = {
    [1] = 'Citations',
    [2] = 'Misdemeanors',
    [3] = 'Felonies',
}

local PenalCode = {
    [1] = {
        [1] = {
            title = 'Driving an illegal Vehicle',
            class = 'Citations',
            id = 'C.T. 1001',
            months = 0,
            fine = 100,
            color = 'green'
        },
        [2] = {
            title = 'Driving On The Wrong Side Of The Road',
            class = 'Citations',
            id = 'C.T. 1002',
            months = 0,
            fine = 250,
            color = 'green'
        },
		[3] = {
            title = 'Driving Without Headlights or Signals',
            class = 'Citations',
            id = 'C.T. 1003',
            months = 0,
            fine = 175,
            color = 'green'
        },
		[4] = {
            title = 'Excessive Vehicle Noise',
            class = 'Citations',
            id = 'C.T. 1004',
            months = 0,
            fine = 200,
            color = 'green'
        },
		[5] = {
            title = 'Failing To Stop At A Stop Sign/Red Light',
            class = 'Citations',
            id = 'C.T. 1005',
            months = 0,
            fine = 250,
            color = 'green'
        },
		[6] = {
            title = 'Failing to Yield To An Emergency Vehicle',
            class = 'Citations',
            id = 'C.T. 1006',
            months = 0,
            fine = 225,
            color = 'green'
        },
		[7] = {
            title = 'Failure to Comply With Vehicle Information',
            class = 'Citations',
            id = 'C.T. 1007',
            months = 0,
            fine = 275,
            color = 'green'
        },
		[8] = {
            title = 'Failure To Maintain Lane',
            class = 'Citations',
            id = 'C.T. 1008',
            months = 0,
            fine = 300,
            color = 'green'
		},
		[9] = {
            title = 'Failure To Provide ID',
            class = 'Citations',
            id = 'C.T. 1009',
            months = 0,
            fine = 300,
            color = 'green'
		},
		[10] = {
            title = 'Failure To Yield',
            class = 'Citations',
            id = 'C.T. 1010',
            months = 0,
            fine = 350,
            color = 'green'
		},
		[11] = {
            title = 'Illegal Parking',
            class = 'Citations',
            id = 'C.T. 1011',
            months = 0,
            fine = 335,
            color = 'green'
		},
		[12] = {
            title = 'Illegal U-Turn',
            class = 'Citations',
            id = 'C.T. 1012',
            months = 0,
            fine = 250,
            color = 'green'
		},
		[13] = {
            title = 'Illegally Driving Off-Road',
            class = 'Citations',
            id = 'C.T. 1013',
            months = 0,
            fine = 275,
            color = 'green'
		},
		[14] = {
            title = 'Impeding Traffic',
            class = 'Citations',
            id = 'C.T. 1014',
            months = 0,
            fine = 225,
            color = 'green'
		},
		[15] = {
            title = 'Refusing a Lawful Command',
            class = 'Citations',
            id = 'C.T. 1015',
            months = 0,
            fine = 225,
            color = 'green'
		},
		[16] = {
            title = 'Speeding Class A',
            class = 'Citations',
            id = 'C.T. 1016',
            months = 0,
            fine = 225,
            color = 'green'
		},
		[17] = {
            title = 'Speeding Class B',
            class = 'Citations',
            id = 'C.T. 1017',
            months = 0,
            fine = 325,
            color = 'green'
		},
		[18] = {
            title = 'Speeding Class C',
            class = 'Citations',
            id = 'C.T. 1018',
            months = 0,
            fine = 425,
            color = 'green'
		},
    },
    [2] = {
        [1] = {
            title = 'Animal Cruelty',
            class = 'Misdemeanors',
            id = 'M.S. 2001',
            months = 10,
            fine = 500,
            color = 'orange'
        },
		[2] = {
            title = 'Burglary',
            class = 'Misdemeanors',
            id = 'M.S. 2002',
            months = 20,
            fine = 400,
            color = 'orange'
        },
		[3] = {
            title = 'Destruction of Property',
            class = 'Misdemeanors',
            id = 'M.S. 2003',
            months = 10,
            fine = 400,
            color = 'orange'
        },
		[4] = {
            title = 'Disorderly Conduct',
            class = 'Misdemeanors',
            id = 'M.S. 2004',
            months = 25,
            fine = 300,
            color = 'orange'
        },
		[5] = {
            title = 'Disrespect of an LEO/EMS',
            class = 'Misdemeanors',
            id = 'M.S. 2005',
            months = 5,
            fine = 250,
            color = 'orange'
        },
		[6] = {
            title = 'Disturbing the Peace',
            class = 'Misdemeanors',
            id = 'M.S. 2006',
            months = 5,
            fine = 250,
            color = 'orange'
        },
		[7] = {
            title = 'Driving Without a License',
            class = 'Misdemeanors',
            id = 'M.S. 2007',
            months = 10,
            fine = 300,
            color = 'orange'
        },
		[8] = {
            title = 'Failure to comply',
            class = 'Misdemeanors',
            id = 'M.S. 2008',
            months = 25,
            fine = 325,
            color = 'orange'
        },
		[9] = {
            title = 'False Report',
            class = 'Misdemeanors',
            id = 'M.S. 2009',
            months = 15,
            fine = 175,
            color = 'orange'
        },
		[10] = {
            title = 'Government Trespassing',
            class = 'Misdemeanors',
            id = 'M.S. 2010',
            months = 25,
            fine = 300,
            color = 'orange'
        },
		[11] = {
            title = 'Harassment',
            class = 'Misdemeanors',
            id = 'M.S. 2011',
            months = 15,
            fine = 400,
            color = 'orange'
        },
		[12] = {
            title = 'Indecent exposure',
            class = 'Misdemeanors',
            id = 'M.S. 2012',
            months = 20,
            fine = 250,
            color = 'orange'
        },
		[13] = {
            title = 'Intimidation',
            class = 'Misdemeanors',
            id = 'M.S. 2013',
            months = 10,
            fine = 200,
            color = 'orange'
        },
		[14] = {
            title = 'Marijuana Cultivation',
            class = 'Misdemeanors',
            id = 'M.S. 2014',
            months = 20,
            fine = 400,
            color = 'orange'
        },
		[15] = {
            title = 'Obstruction of Justice',
            class = 'Misdemeanors',
            id = 'M.S. 2015',
            months = 25,
            fine = 250,
            color = 'orange'
        },
		[16] = {
            title = 'Disturbing the Peace',
            class = 'Misdemeanors',
            id = 'M.S. 2015',
            months = 15,
            fine = 300,
            color = 'orange'
        },
		[17] = {
            title = 'Providing False Information',
            class = 'Misdemeanors',
            id = 'M.S. 2016',
            months = 15,
            fine = 300,
            color = 'orange'
        },
		[18] = {
            title = 'Public Intoxication',
            class = 'Misdemeanors',
            id = 'M.S. 2017',
            months = 5,
            fine = 300,
            color = 'orange'
        },
		[19] = {
            title = 'Receiving Stolen Property',
            class = 'Misdemeanors',
            id = 'M.S. 2018',
            months = 20,
            fine = 400,
            color = 'orange'
        },
		[20] = {
            title = 'Reckless Driving',
            class = 'Misdemeanors',
            id = 'M.S. 2019',
            months = 30,
            fine = 550,
            color = 'orange'
        },
		[21] = {
            title = 'Trespassing',
            class = 'Misdemeanors',
            id = 'M.S. 2020',
            months = 20,
            fine = 150,
            color = 'orange'
        },
		[22] = {
            title = 'Verbal Threat Towards A Person',
            class = 'Misdemeanors',
            id = 'M.S. 2021',
            months = 20,
            fine = 200,
            color = 'orange'
        },
    },
    [3] = {
        [1] = {
            title = 'Accessory After Fact',
            class = 'Felonies',
            id = 'F.L. 3001',
            months = 15,
            fine = 500,
            color = 'red'
        },
		[2] = {
            title = 'Aggravated Robbery',
            class = 'Felonies',
            id = 'F.L. 3002',
            months = 25,
            fine = 600,
            color = 'red'
        },
		[3] = {
            title = 'Aggravated Threats on a Officer/EMS',
            class = 'Felonies',
            id = 'F.L. 3003',
            months = 25,
            fine = 550,
            color = 'red'
        },
		[4] = {
            title = 'Assault',
            class = 'Felonies',
            id = 'F.L. 3004',
            months = 30,
            fine = 600,
            color = 'red'
        },
		[5] = {
            title = 'Attempted Murder',
            class = 'Felonies',
            id = 'F.L. 3005',
            months = 35,
            fine = 650,
            color = 'red'
        },
		[6] = {
            title = 'Bank Robbery',
            class = 'Felonies',
            id = 'F.L. 3006',
            months = 35,
            fine = 575,
            color = 'red'
        },
		[7] = {
            title = 'Brandishing a Weapon',
            class = 'Felonies',
            id = 'F.L. 3007',
            months = 15,
            fine = 350,
            color = 'red'
        },
		[8] = {
            title = 'Bribery',
            class = 'Felonies',
            id = 'F.L. 3007',
            months = 10,
            fine = 200,
            color = 'red'
        },
		[9] = {
            title = 'Concealing Evidence',
            class = 'Felonies',
            id = 'F.L. 3008',
            months = 10,
            fine = 200,
            color = 'red'
        },
		[10] = {
            title = 'Criminal Threats/Conspiracy',
            class = 'Felonies',
            id = 'F.L. 3009',
            months = 10,
            fine = 225,
            color = 'red'
        },
		[11] = {
            title = 'Destruction of Government Property',
            class = 'Felonies',
            id = 'F.L. 3010',
            months = 15,
            fine = 325,
            color = 'red'
        },
		[12] = {
            title = 'Driving Under The Influence',
            class = 'Felonies',
            id = 'F.L. 3011',
            months = 25,
            fine = 550,
            color = 'red'
        },
		[13] = {
            title = 'Drug Distribution',
            class = 'Felonies',
            id = 'F.L. 3012',
            months = 30,
            fine = 400,
            color = 'red'
        },
		[14] = {
            title = 'Drug Manufacturing',
            class = 'Felonies',
            id = 'F.L. 3013',
            months = 30,
            fine = 400,
            color = 'red'
        },
		[15] = {
            title = 'Drug Possession',
            class = 'Felonies',
            id = 'F.L. 3014',
            months = 30,
            fine = 400,
            color = 'red'
        },
		[16] = {
            title = 'Fleeing and Evading',
            class = 'Felonies',
            id = 'F.L. 3015',
            months = 25,
            fine = 500,
            color = 'red'
        },
		[17] = {
            title = 'Grand Theft Auto',
            class = 'Felonies',
            id = 'F.L. 3016',
            months = 10,
            fine = 300,
            color = 'red'
        },
		[18] = {
            title = 'Hit & Run',
            class = 'Felonies',
            id = 'F.L. 3017',
            months = 15,
            fine = 200,
            color = 'red'
        },
		[19] = {
            title = 'Impersonating Emergency Services',
            class = 'Felonies',
            id = 'F.L. 3018',
            months = 20,
            fine = 300,
            color = 'red'
        },
		[20] = {
            title = 'Kidnapping',
            class = 'Felonies',
            id = 'F.L. 3019',
            months = 35,
            fine = 500,
            color = 'red'
        },
		[21] = {
            title = 'Multiple Murders',
            class = 'Felonies',
            id = 'F.L. 3020',
            months = 60,
            fine = 1500,
            color = 'red'
        },
		[22] = {
            title = 'Murder',
            class = 'Felonies',
            id = 'F.L. 3021',
            months = 35,
            fine = 1000,
            color = 'red'
        },
		[23] = {
            title = 'Possession of a Class 2 Weapon',
            class = 'Felonies',
            id = 'F.L. 3022',
            months = 25,
            fine = 600,
            color = 'red'
        },
		[24] = {
            title = 'Possession of Contraband',
            class = 'Felonies',
            id = 'F.L. 3023',
            months = 25,
            fine = 600,
            color = 'red'
        },
		[25] = {
            title = 'Possession of Stolen Jewelry',
            class = 'Felonies',
            id = 'F.L. 3024',
            months = 25,
            fine = 600,
            color = 'red'
        },
		[26] = {
            title = 'Reckless Endangerment',
            class = 'Felonies',
            id = 'F.L. 3025',
            months = 35,
            fine = 500,
            color = 'red'
        },
		[27] = {
            title = 'Robbery',
            class = 'Felonies',
            id = 'F.L. 3026',
            months = 30,
            fine = 450,
            color = 'red'
        },
		[28] = {
            title = 'Robbery of an Armoured Truck',
            class = 'Felonies',
            id = 'F.L. 3027',
            months = 35,
            fine = 500,
            color = 'red'
        },
		[29] = {
            title = 'Theft of an Emergency Vehicle',
            class = 'Felonies',
            id = 'F.L. 3028',
            months = 30,
            fine = 450,
            color = 'red'
        },
		[30] = {
            title = 'Transportation Of Stolen Cargo',
            class = 'Felonies',
            id = 'F.L. 3029',
            months = 25,
            fine = 375,
            color = 'red'
        },
		[31] = {
            title = 'Unlawful Discharge of a Firearm',
            class = 'Felonies',
            id = 'F.L. 3030',
            months = 40,
            fine = 700,
            color = 'red'
        },
		[32] = {
            title = 'Unlawful Discharge of a Firearm Inside a Govt. Building',
            class = 'Felonies',
            id = 'F.L. 3032',
            months = 45,
            fine = 750,
            color = 'red'
        },
		[33] = {
            title = 'Unlawful Possession of a Firearm Without a License',
            class = 'Felonies',
            id = 'F.L. 3033',
            months = 40,
            fine = 700,
            color = 'red'
        },
		[34] = {
            title = 'Weapon Distribution',
            class = 'Felonies',
            id = 'F.L. 3034',
            months = 40,
            fine = 600,
            color = 'red'
        },
    }
}

local function IsCidFelon(sentCid, cb)
    if sentCid then
        exports.oxmysql:execute('SELECT charges FROM pd_convictions WHERE cid = @cid', {
            ["@cid"] = sentCid
        }, function(convictions)
            local Charges = {}
            for i = 1, #convictions do
                local currCharges = json.decode(convictions[i]['charges'])
                for x = 1, #currCharges do
                    table.insert(Charges, currCharges[x])
                end
            end
            for i = 1, #Charges do
                for p = 1, #PenalCode do
                    for x = 1, #PenalCode[p] do
                        if PenalCode[p][x]['title'] == Charges[i] then
                            if PenalCode[p][x]['class'] == 'Felony' then
                                cb(true)
                                return
                            end
                            break
                        end
                    end
                end
            end
            cb(false)
        end)
    end
end

exports('IsCidFelon', IsCidFelon) -- exports['erp_mdt']:IsCidFelon()

--[[RegisterCommand("isfelon", function(source, args, rawCommand)
    IsCidFelon(1998, function(res)
        print(res)
    end)
end, false)]]

RegisterNetEvent('erp_mdt:getPenalCode')
AddEventHandler('erp_mdt:getPenalCode', function()
    TriggerClientEvent('erp_mdt:getPenalCode', source, PenalCodeTitles, PenalCode)
end)

local policeJobs = {
    ['police'] = true,
}

RegisterNetEvent('erp_mdt:toggleDuty')
AddEventHandler('erp_mdt:toggleDuty', function(cid, status)
    local xPlayer = ESX.GetPlayerFromId(source)
    local player = ESX.GetPlayerFromIdentifier(cid)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            local isPolice = false
            if policeJobs[player.job.name] then
                isPolice = true
            end
            exports.oxmysql:executeSync("UPDATE users SET duty = @duty WHERE identifier = @cid", {
                ["@duty"] = status,
                ["@cid"] = cid
            })
            if status == 0 then
                TriggerEvent('erp_mdt:AddLog',
                    xPlayer.name .. " set " .. player.name .. '\'s duty to 10-7')
            else
                TriggerEvent('erp_mdt:AddLog',
                    xPlayer.name .. " set " .. player.name .. '\'s duty to 10-8')
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:setCallsign')
AddEventHandler('erp_mdt:setCallsign', function(cid, newcallsign)
    local xPlayer = ESX.GetPlayerFromId(source)
    local player = ESX.GetPlayerFromIdentifier(cid)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            SetResourceKvp(cid .. '-callsign', newcallsign)
            TriggerClientEvent('erp_mdt:updateCallsign', player.source, newcallsign)
            TriggerEvent('erp_mdt:AddLog',
                xPlayer.name .. " set " .. player['name'] .. '\'s callsign to ' .. newcallsign)
        end
    end
end)

local function fuckme(cid, incident, data, cb)
    cb(exports.oxmysql:executeSync('SELECT * FROM pd_convictions WHERE cid = @cid AND linkedincident = @linkedincident', {
        ["@cid"] = cid,
        ["@linkedincident"] = id
    }), data)
end

RegisterNetEvent('erp_mdt:saveIncident')
AddEventHandler('erp_mdt:saveIncident', function(id, title, information, tags, officers, civilians, evidence, associated, time)
    local player = ESX.GetPlayerFromId(source)
    if player then
        if (player.job.name == 'police' or player.job.name == 'doj') then
            if id == 0 then
                exports.oxmysql:insert(
                    'INSERT INTO `pd_incidents` (`author`, `title`, `details`, `tags`, `officersinvolved`, `civsinvolved`, `evidence`, `time`) VALUES (@author, @title, @details, @tags, @officersinvolved, @civsinvolved, @evidence, @time)',
                    {
                        ["@author"] = player.name,
                        ["@title"] = title,
                        ["@details"] = information,
                        ["@tags"] = json.encode(tags),
                        ["@officersinvolved"] = json.encode(officers),
                        ["@civsinvolved"] = json.encode(civilians),
                        ["@evidence"] = json.encode(evidence),
                        ["@time"] = time
                    }, function(infoResult)
                        if infoResult then
                            for i = 1, #associated do
                                exports.oxmysql:executeSync(
                                    'INSERT INTO `pd_convictions` (`cid`, `linkedincident`, `warrant`, `guilty`, `processed`, `associated`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (@cid, @linkedincident, @warrant, @guilty, @processed, @associated, @charges, @fine, @sentence, @recfine, @recsentence, @time)',
                                    {
                                        ["@cid"] = associated[i]['Cid'],
                                        ["@linkedincident"] = infoResult,
                                        ["@warrant"] = associated[i]['Warrant'],
                                        ["@guilty"] = associated[i]['Guilty'],
                                        ["@processed"] = associated[i]['Processed'],
                                        ["@associated"] = associated[i]['Isassociated'],
                                        ["@charges"] = json.encode(associated[i]['Charges']),
                                        ["@fine"] = tonumber(associated[i]['Fine']),
                                        ["@sentence"] = tonumber(associated[i]['Sentence']),
                                        ["@recfine"] = tonumber(associated[i]['recfine']),
                                        ["@recsentence"] = tonumber(associated[i]['recsentence']),
                                        ["@time"] = time
                                    })
                            end
                            TriggerClientEvent('erp_mdt:updateIncidentDbId', player.source, infoResult)
                            -- TriggerEvent('erp_mdt:AddLog', "A vehicle with the plate ("..plate..") was added to the vehicle information database by "..player['name'])
                        end
                    end)
            elseif id > 0 then
                exports.oxmysql:executeSync(
                    "UPDATE pd_incidents SET title = @title, details = @details, civsinvolved = @civsinvolved, tags = @tags, officersinvolved = @officersinvolved, evidence = @evidence WHERE id = @id",
                    {
                        ["@title"] = title,
                        ["@details"] = information,
                        ["@tags"] = json.encode(tags),
                        ["@officersinvolved"] = json.encode(officers),
                        ["@civsinvolved"] = json.encode(civilians),
                        ["@evidence"] = json.encode(evidence),
                        ["@id"] = id
                    })
                for i = 1, #associated do
                    TriggerEvent('erp_mdt:handleExistingConvictions', associated[i], id, time)
                end
            end
        end
    end
end)

AddEventHandler('erp_mdt:handleExistingConvictions', function(data, incidentid, time)
    exports.oxmysql:execute('SELECT * FROM pd_convictions WHERE cid = @cid AND linkedincident = @linkedincident', {
        ["@cid"] = data['Cid'],
        ["@linkedincident"] = incidentid
    }, function(convictionRes)
        if convictionRes and convictionRes[1] and convictionRes[1]['id'] then
            exports.oxmysql:executeSync(
                'UPDATE pd_convictions SET cid = @cid, linkedincident = @linkedincident, warrant = @warrant, guilty = @guilty, processed = @processed, associated = @associated, charges = @charges, fine = @fine, sentence = @sentence, recfine = @recfine, recsentence = @recsentence WHERE cid = @cid AND linkedincident = @linkedincident',
                {
                   ["@cid"] = data['Cid'],
                    ["@linkedincident"] = incidentid,
                    ["@warrant"] = data['Warrant'],
                    ["@guilty"] = data['Guilty'],
                    ["@processed"] = data['Processed'],
                    ["@associated"] = data['Isassociated'],
                    ["@charges"] = json.encode(data['Charges']),
                    ["@fine"] = tonumber(data['Fine']),
                    ["@sentence"] = tonumber(data['Sentence']),
                    ["@recfine"] = tonumber(data['recfine']),
                    ["@recsentence"] = tonumber(data['recsentence'])
                })
        else
            exports.oxmysql:executeSync(
                'INSERT INTO `pd_convictions` (`cid`, `linkedincident`, `warrant`, `guilty`, `processed`, `associated`, `charges`, `fine`, `sentence`, `recfine`, `recsentence`, `time`) VALUES (@cid, @linkedincident, @warrant, @guilty, @processed, @associated, @charges, @fine, @sentence, @recfine, @recsentence, @time)',
                {
                    ["@cid"] = tonumber(data['Cid']),
                    ["@linkedincident"] = incidentid,
                    ["@warrant"] = data['Warrant'],
                    ["@guilty"] = data['Guilty'],
                    ["@processed"] = data['Processed'],
                    ["@associated"] = data['Isassociated'],
                    ["@charges"] = json.encode(data['Charges']),
                    ["@fine"] = tonumber(data['Fine']),
                    ["@sentence"] = tonumber(data['Sentence']),
                    ["@recfine"] = tonumber(data['recfine']),
                    ["@recsentence"] = tonumber(data['recsentence']),
                    ["@time"] = time
                })
        end
    end)
end)

RegisterNetEvent('erp_mdt:removeIncidentCriminal')
AddEventHandler('erp_mdt:removeIncidentCriminal', function(cid, incident)
    exports.oxmysql:executeSync('DELETE FROM pd_convictions WHERE cid = @cid AND linkedincident = @linkedincident', {
        ["@cid"] = cid,
        ["@linkedincident"] = incident
    })
end)

-- Dispatch

RegisterNetEvent('erp_mdt:setWaypoint')
AddEventHandler('erp_mdt:setWaypoint', function(callid)
    local player = ESX.GetPlayerFromId(source)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                local calls = exports['erp_dispatch']:GetDispatchCalls()
                TriggerClientEvent('erp_mdt:setWaypoint', player.source, calls[callid])
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:callDetach')
AddEventHandler('erp_mdt:callDetach', function(callid)
    local player = ESX.GetPlayerFromId(source)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                TriggerEvent('dispatch:removeUnit', callid, player, function(newNum)
                    TriggerClientEvent('erp_mdt:callDetach', -1, callid, newNum)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:callAttach')
AddEventHandler('erp_mdt:callAttach', function(callid)
    local player = ESX.GetPlayerFromId(source)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                TriggerEvent('dispatch:addUnit', callid, player, function(newNum)
                    TriggerClientEvent('erp_mdt:callAttach', -1, callid, newNum)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:attachedUnits')
AddEventHandler('erp_mdt:attachedUnits', function(callid)
    local player = ESX.GetPlayerFromId(source)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                local calls = exports['erp_dispatch']:GetDispatchCalls()
                TriggerClientEvent('erp_mdt:attachedUnits', player.source, calls[callid]['units'], callid)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:callDispatchDetach')
AddEventHandler('erp_mdt:callDispatchDetach', function(callid, cid)
    local player = ESX.GetPlayerFromIdentifier(cid)
    local callid = tonumber(callid)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                TriggerEvent('dispatch:removeUnit', callid, player, function(newNum)
                    TriggerClientEvent('erp_mdt:callDetach', -1, callid, newNum)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:setDispatchWaypoint')
AddEventHandler('erp_mdt:setDispatchWaypoint', function(callid, cid)
    local player = ESX.GetPlayerFromIdentifier(cid)
    local callid = tonumber(callid)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                local calls = exports['erp_dispatch']:GetDispatchCalls()
                TriggerClientEvent('erp_mdt:setWaypoint', player.source, calls[callid])
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:callDragAttach')
AddEventHandler('erp_mdt:callDragAttach', function(callid, cid)
    local player = ESX.GetPlayerFromIdentifier(cid)
    local callid = tonumber(callid)
    if player then
        if player.job.name == 'police' or player.job.name == 'ambulance' then
            if callid then
                TriggerEvent('dispatch:addUnit', callid, player, function(newNum)
                    TriggerClientEvent('erp_mdt:callAttach', -1, callid, newNum)
                end)
            end
        end
    end
end)

RegisterNetEvent('erp_mdt:setWaypoint:unit')
AddEventHandler('erp_mdt:setWaypoint:unit', function(cid)
    local source = source
    local me = ESX.GetPlayerFromId(source)
    local player = ESX.GetPlayerFromIdentifier(cid)
    if player then
        TriggerClientEvent('erp_notifications:client:SendAlert', player.source, {
            type = 'inform',
            text = me['name'] .. ' set a waypoint on you!',
            length = 5000
        })
        TriggerClientEvent('erp_mdt:setWaypoint:unit', source, GetEntityCoords(GetPlayerPed(player.source)))
    end
end)

-- Dispatch chat

local dispatchmessages = {}

--[[
	profilepic
	name
	message
	time
]]

local function PpPpPpic(sex, profilepic)
    if profilepic then
        return profilepic
    end
    if sex == "f" then
        return "img/female.png"
    end
    return "img/male.png"
end

RegisterNetEvent('erp_mdt:sendMessage')
AddEventHandler('erp_mdt:sendMessage', function(message, time)
    if message and time then
        local player = ESX.GetPlayerFromId(source)
        if player then
            exports.oxmysql:execute("SELECT id, identifier, profilepic, sex FROM `users` WHERE identifier = @id LIMIT 1", {
                ["@id"] = player['identifier'] -- % wildcard, needed to search for all alike results
            }, function(data)
                if data and data[1] then
                    --print(json.encode(data))
                    local ProfilePicture = PpPpPpic(data[1]['sex'], data[1]['profilepic'])
                    local callsign = GetCallsign(player['identifier']) --Need to manually set in DB or it errors out
                    local Item = {
                        profilepic = ProfilePicture,
                        callsign = callsign[1].callsign,
                        cid = player['identifier'],
                        name = '(' .. callsign[1].callsign .. ') ' .. player['name'],
                        message = message,
                        time = time,
                        job = player['job']['name']
                    }
                    table.insert(dispatchmessages, Item)
                    TriggerClientEvent('erp_mdt:dashboardMessage', -1, Item)
                    -- Send to all clients, for auto updating stuff, ya dig.
                end
            end)
        end
    end
end)

AddEventHandler('erp_mdt:open', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and
            (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance')) then
            TriggerClientEvent('erp_mdt:dashboardMessages', xPlayer['source'], dispatchmessages)
        end
    end
end)

RegisterNetEvent('erp_mdt:refreshDispatchMsgs')
AddEventHandler('erp_mdt:refreshDispatchMsgs', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and
            (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance' or xPlayer.job.name == 'doj')) then
            TriggerClientEvent('erp_mdt:dashboardMessages', xPlayer['source'], dispatchmessages)
        end
    end
end)

RegisterNetEvent('erp_mdt:getCallResponses')
AddEventHandler('erp_mdt:getCallResponses', function(callid)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance')) then
            local calls = exports['erp_dispatch']:GetDispatchCalls()
            TriggerClientEvent('erp_mdt:getCallResponses', xPlayer.source, calls[callid]['responses'], callid)
        end
    end
end)

RegisterNetEvent('erp_mdt:sendCallResponse')
AddEventHandler('erp_mdt:sendCallResponse', function(message, time, callid)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.job and (xPlayer.job.name == 'police' or (xPlayer.job.name == 'ambulance')) then
            TriggerEvent('dispatch:sendCallResponse', xPlayer, callid, message, time, function(isGood)
                if isGood then
                    TriggerClientEvent('erp_mdt:sendCallResponse', -1, message, time, callid, xPlayer.name)
                end
            end)
        end
    end
end)

CreateThread(function()
    Wait(1800000)
    dispatchmessages = {}
end)

