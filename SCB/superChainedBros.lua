-- name: Super Chained Bros v1.0
-- description: This mod adds mechanics consisting of chaining players together to limit their movements and they have to cooperate when doing parkour.\nAuthor: ProfeJavix
-- pausable: false

--#region Constants
local partSpacing = 50
local playerYMod = 50
local maxCenterDist = 350
local chainKB = 10
--#endregion

--#region Variables
local gettingUp = false
local chainCenter = { x = 0, y = 0, z = 0 } ---@type Vec3f
--#endregion

--#region Localize functions
local tableInsert, networkIsServer, hookChatCommand, hookEvent, hookBhv, chatMsg, popup, spawnObj, vec3f_dist, vec3f_dot =
    table.insert, network_is_server, hook_chat_command, hook_event, hook_behavior, djui_chat_message_create,
    djui_popup_create,
    spawn_non_sync_object, vec3f_dist, vec3f_dot
--#endregion

--#region ChainParts behaviour
--- @param o Object
function bhvChainInit(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE
    obj_set_billboard(o)
    cur_obj_scale(0.7)
end

local id_bhv_chain = hookBhv(nil, OBJ_LIST_GENACTOR, true, bhvChainInit, obj_mark_for_deletion)
--#endregion

--#region Chaining Commands
function chain(msg)
    if msg ~= "" then
        return false
    end

    if gPlayerSyncTable[0].chained then
        popup(gNetworkPlayers[0].name .. " is already chained.", 1)
    elseif canBeChained() then
        gPlayerSyncTable[0].chained = true
    else
        popup(gNetworkPlayers[0].name .. " is too far from the chained players.", 1)
    end
    return true
end

function unchain(msg)
    if msg ~= "" then
        return false
    end

    if gPlayerSyncTable[0].chained then
        gPlayerSyncTable[0].chained = false
    else
        popup(gNetworkPlayers[0].name .. " is not chained.", 1)
    end
    return true
end
--#endregion

--#region Chaining Logic
---@param m MarioState
function mario_update(m)
    if m.playerIndex == 0 and gNetworkPlayers[0].connected then
        mario_update_local(m)
    end
end

--- @param m MarioState
function mario_update_local(m)
    local chainedPlayersPositions = {}
    local count = 0
    local chainedPlayersIndexes = getChainedPlayersInArea()
    for _, i in ipairs(chainedPlayersIndexes) do
        local pos = {
            x = gMarioStates[i].pos.x,
            y = gMarioStates[i].pos.y + playerYMod,
            z = gMarioStates[i].pos.z
        }
        tableInsert(chainedPlayersPositions, pos)
        count = count + 1
    end

    if count > 1 then
        drawChainsForPlayers(chainedPlayersPositions, chainedPlayersIndexes)
        handleChainedPhysics(m)
    end
end

---@param chainedPlayersPositions Vec3f[]
---@param chainedPlayersIndexes integer[]
function drawChainsForPlayers(chainedPlayersPositions, chainedPlayersIndexes)
    setCenter(chainedPlayersPositions)
    for _, playerIdx in ipairs(chainedPlayersIndexes) do
        local m = gMarioStates[playerIdx]
        local mPos = {
            x = m.pos.x,
            y = m.pos.y + playerYMod,
            z = m.pos.z
        }
        local direction = getDirToCenter(mPos)
        local dist = vec3f_dist(mPos, chainCenter)
        local currPos = {
            x = chainCenter.x,
            y = chainCenter.y,
            z = chainCenter.z
        }
        while dist >= 0 do
            spawnObj(id_bhv_chain, E_MODEL_METALLIC_BALL, currPos.x, currPos.y, currPos.z, function() end)
            currPos = {
                x = currPos.x + direction.x * partSpacing,
                y = currPos.y + direction.y * partSpacing,
                z = currPos.z + direction.z * partSpacing
            }
            dist = dist - partSpacing
        end
    end
end

---@param m MarioState
function handleChainedPhysics(m)
    if gPlayerSyncTable[m.playerIndex].chained then
        local dist = vec3f_dist(m.pos, chainCenter)
        if isMarioMovingAway(m.pos, m.vel) and dist >= maxCenterDist then
            if m.forwardVel > 0 then
                m.forwardVel = -chainKB
            else
                m.forwardVel = chainKB
            end

            if (m.action & ACT_FLAG_AIR) ~= 0 then

                if m.pos.x < chainCenter.x - maxCenterDist then
                    m.vel.x = chainKB
                elseif m.pos.x > chainCenter.x + maxCenterDist then
                    m.vel.x = -chainKB
                end

                if m.pos.y < chainCenter.y - maxCenterDist then
                    m.vel.y = chainKB
                    gettingUp = true
                    set_mario_action(m, ACT_IDLE, 0)
                elseif m.pos.y > chainCenter.y + maxCenterDist then
                    m.vel.y = -chainKB
                end

                if m.pos.z < chainCenter.z - maxCenterDist then
                    m.vel.z = chainKB
                elseif m.pos.z > chainCenter.z + maxCenterDist then
                    m.vel.z = -chainKB
                end
            end
        end
        if gettingUp and (m.controller.buttonPressed & A_BUTTON) ~= 0 then
            gettingUp = false
            m.vel.y = 60
        end
    end
end
--#endregion

--#region Utils
---@return integer[]
function getChainedPlayersInArea()
    local playerIndexes = {}
    for i = 0, (MAX_PLAYERS - 1) do
        if gNetworkPlayers[i].connected and gPlayerSyncTable[i].chained and gNetworkPlayers[i].currLevelNum == gNetworkPlayers[0].currLevelNum then
            tableInsert(playerIndexes, i)
        end
    end
    return playerIndexes
end

---@return boolean
function canBeChained()
    local chainedPlayers = getChainedPlayersInArea()
    local dist = 0
    if #chainedPlayers == 1 then
        local otherPos = gMarioStates[chainedPlayers[1]].pos
        dist = vec3f_dist(gMarioStates[0].pos, otherPos) / 2
    elseif #chainedPlayers > 1 then
        dist = vec3f_dist(gMarioStates[0].pos, chainCenter)
    end
    return dist <= maxCenterDist
end

function hasServerRepeatedNames(name)
    local count = 0
    for i = 0, (MAX_PLAYERS - 1) do
        if count > 1 then
            return true
        end
        if gNetworkPlayers[i].name == name then
            count = count + 1
        end
    end
    return false
end

---@param positions Vec3f[]
function setCenter(positions)
    local sumX, sumY, sumZ = 0, 0, 0
    for _, val in ipairs(positions) do
        sumX = sumX + val.x
        sumY = sumY + val.y
        sumZ = sumZ + val.z
    end
    chainCenter = {
        x = sumX / #positions,
        y = sumY / #positions,
        z = sumZ / #positions
    }
end

---@param mPos Vec3f
---@return Vec3f
function getDirToCenter(mPos)
    local mag = math.sqrt((mPos.x - chainCenter.x) ^ 2 + (mPos.y - chainCenter.y) ^ 2 + (mPos.z - chainCenter.z) ^ 2)
    return {
        x = (mPos.x - chainCenter.x) / mag,
        y = (mPos.y - chainCenter.y) / mag,
        z = (mPos.z - chainCenter.z) / mag
    }
end

---@param mPos Vec3f
---@param velocity Vec3f
---@return boolean
function isMarioMovingAway(mPos, velocity)
    local betVect = {
        x = chainCenter.x - mPos.x,
        y = chainCenter.y - mPos.y,
        z = chainCenter.z - mPos.z
    }
    return vec3f_dot(betVect, velocity) < 0
end
--#endregion

--#region Hooks
hookEvent(HOOK_MARIO_UPDATE, mario_update)
hookChatCommand("scb-chain", "- Chains your player to the other chained ones.", chain)
hookChatCommand("scb-unchain", "- Releases the chains of your player.", unchain)
--#endregion