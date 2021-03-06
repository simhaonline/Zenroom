-- This file is part of Zenroom (https://zenroom.dyne.org)
--
-- Copyright (C) 2018-2019 Dyne.org foundation
-- designed, written and maintained by Denis Roio <jaromil@dyne.org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of the
-- License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.



--- Zencode data internals


-- init schemas
function ZEN.add_schema(arr)
   local _illegal_schemas = { -- const
	  whoami = true
   }
   for k,v in pairs(arr) do
	  -- check overwrite / duplicate to avoid scenario namespace clash
	  ZEN.assert(not ZEN.schemas[k], "Add schema denied, already registered schema: "..k)
	  ZEN.assert(not _illegal_schemas[k], "Add schema denied, reserved name: "..k)
	  ZEN.schemas[k] = v
   end
end


-- basic encoding schemas
ZEN.add_schema({
	  base64 = function(obj) return ZEN:convert(obj, OCTET.from_base64) end,
	  url64  = function(obj) return ZEN:convert(obj, OCTET.from_url64)  end,
	  str =    function(obj) return ZEN:convert(obj, OCTET.from_string) end,
})


-- init statements
function Given(text, fn)
   -- xxx(3,"Scenario '"..ZEN.scenario.."' add given statement: "..text)
   ZEN.assert(not ZEN.given_steps[text],
   			  "Conflicting statement loaded by scenario: "..text)
   ZEN.given_steps[text] = fn
end
function When(text, fn)
   -- xxx(3,"Scenario '"..ZEN.scenario.."' add when statement: "..text)
   ZEN.assert(not ZEN.when_steps[text],
   			  "Conflicting statement loaded by scenario: "..text)
   ZEN.when_steps[text] = fn
end
function Then(text, fn)
   -- xxx(3,"Scenario '"..ZEN.scenario.."' add then statement: "..text)
   ZEN.assert(not ZEN.then_steps[text],
   			  "Conflicting statement loaded by scenario : "..text)
   ZEN.then_steps[text] = fn
end


-- debug functions
Given("debug", function() ZEN.debug() end)
When("debug",  function() ZEN.debug() end)
Then("debug",  function() ZEN.debug() end)

-- the main security concern in this Zencode module is that no data
-- passes without validation from IN to ACK or from inline input.

-- TODO: return the prefix of an encoded string if found
ZEN.prefix = function(str)
   t = type(str)
   if t ~= "string" then return nil end
   if str:sub(4,4) ~= ":" then return nil end
   return str:sub(1,3)
end

ZEN.get = function(obj, key, conversion)
   ZEN.assert(obj, "ZEN.get no object found")
   ZEN.assert(type(key) == "string", "ZEN.get key is not a string")
   ZEN.assert(not conversion or type(conversion) == 'function',
			  "ZEN.get invalid conversion function")
   local k = obj[key]
   ZEN.assert(k, "Key not found in object conversion: "..key)
   local res = nil
   local t = type(k)
   if iszen(t) and conversion then res = conversion(k) goto ok end
   if iszen(t) and not conversion then res = k goto ok end
   if t == 'string' and conversion == str then res = k goto ok end
   if t == 'string' and conversion and conversion ~= str then
	  res = conversion(ZEN:import(k)) goto ok end
   if t == 'string' and not conversion then res = ZEN:import(k) goto ok end
   ::ok::
   assert(ZEN.OK and res)
   return res
end


-- import function to have recursion of nested data structures
-- according to their stated schema
function ZEN:valid(sname, obj)
   ZEN.assert(sname, "Import error: schema name is nil")
   ZEN.assert(obj, "Import error: object is nil '"..sname.."'")
   local s = ZEN.schemas[sname]
   ZEN.assert(s, "Import error: schema not found '"..sname.."'")
   ZEN.assert(type(s) == 'function', "Import error: schema is not a function '"..sname.."'")
   return s(obj)
end

--- Given block (IN read-only memory)
-- @section Given

---
-- Declare 'my own' name that will refer all uses of the 'my' pronoun
-- to structures contained under this name.
--
-- @function ZEN:Iam(name)
-- @param name own name to be saved in WHO
function ZEN:Iam(name)
   if name then
	  ZEN.assert(not WHO, "Identity already defined in WHO")
	  ZEN.assert(type(name) == "string", "Own name not a string")
	  WHO = name
   else
	  ZEN.assert(WHO, "No identity specified in WHO")
   end
   assert(ZEN.OK)
end


-- local function used inside ZEN:pick*
-- try obj.*.what (TODO: exclude KEYS and WHO)
local function inside_pick(obj, what)
   ZEN.assert(obj, "ZEN:pick object is nil")
   -- ZEN.assert(I.spy(type(obj)) == "table", "ZEN:pick object is not a table")
   ZEN.assert(type(what) == "string", "ZEN:pick object index is not a string")
   local got
   if type(obj) == 'string' then  got = obj
   else got = obj[what] end
   if got then
	  -- ZEN:ftrace("inside_pick found "..what.." at object root")
	  goto gotit
   end
   for k,v in pairs(obj) do -- search 1 deeper
      if type(v) == "table" and v[what] then
         got = v[what]
         -- ZEN:ftrace("inside_pick found "..k.."."..what)
         break
      end
   end
   ::gotit::
   return got
end

---
-- Pick a generic data structure from the <b>IN</b> memory
-- space. Looks for named data on the first and second level and makes
-- it ready for @{validate} or @{ack}.
--
-- @function ZEN:pick(name, data)
-- @param name string descriptor of the data object
-- @param data[opt] optional data object (default search inside IN.*)
-- @return true or false
function ZEN:pick(what, obj)
   if obj then -- object provided by argument
	  TMP = { data = obj,
			  root = nil,
			  schema = what,
			  valid = false }
	  return(ZEN.OK)
   end
   local got
   got = inside_pick(IN.KEYS, what) or inside_pick(IN,what)
   ZEN.assert(got, "Cannot find '"..what.."' anywhere")
   TMP = { root = nil,
		   data = got,
		   valid = false,
		   schema = what }
   assert(ZEN.OK)
   ZEN:ftrace("pick found "..what)
end

---
-- Pick a data structure named 'what' contained under a 'section' key
-- of the at the root of the <b>IN</b> memory space. Looks for named
-- data at the first and second level underneath IN[section] and moves
-- it to TMP[what][section], ready for @{validate} or @{ack}. If
-- TMP[what] exists already, every new entry is added as a key/value
--
-- @function ZEN:pickin(section, name)
-- @param section string descriptor of the section containing the data
-- @param name string descriptor of the data object
-- @return true or false
function ZEN:pickin(section, what)
   ZEN.assert(section, "No section specified")
   local root -- section
   local got  -- what
   root = inside_pick(IN.KEYS,section)
   if root then --    IN KEYS
	  got = inside_pick(root, what)
	  if got then goto found end
   end
   root = inside_pick(IN,section)
   if root then --    IN
	  got = inside_pick(root, what)
	  if got then goto found end
   end
   ZEN.assert(got, "Cannot find '"..what.."' inside '"..section.."'")
   -- TODO: check all corner cases to make sure TMP[what] is a k/v map
   ::found::
   TMP = { root = section,
		   data = got,
		   valid = false,
		   schema = what }
   assert(ZEN.OK)
   ZEN:ftrace("pickin found "..what.." in "..section)
end

---
-- Optional step inside the <b>Given</b> block to execute schema
-- validation on the last data structure selected by @{pick}.
--
-- @function ZEN:validate(name)
-- @param name string descriptor of the data object
-- @param schema[opt] string descriptor of the schema to validate
-- @return true or false
function ZEN:validate(name, schema)
   schema = schema or TMP.schema or name -- if no schema then coincides with name
   ZEN.assert(name, "ZEN:validate error: argument is nil")
   ZEN.assert(TMP, "ZEN:validate error: TMP is nil")
   -- ZEN.assert(TMP.schema, "ZEN:validate error: TMP.schema is nil")
   -- ZEN.assert(TMP.schema == name, "ZEN:validate() TMP does not contain "..name)
   local got = TMP.data -- inside_pick(TMP,name)
   ZEN.assert(TMP.data, "ZEN:validate error: data not found in TMP for schema "..name)
   local s = ZEN.schemas[schema]
   ZEN.assert(s, "ZEN:validate error: "..schema.." schema not found")
   ZEN.assert(type(s) == 'function', "ZEN:validate error: schema is not a function for "..schema)
   ZEN:ftrace("validate "..name.. " with schema "..schema)
   local res = s(TMP.data) -- ignore root
   ZEN.assert(res, "ZEN:validate error: validation failed for "..name.." with schema "..schema)
   TMP.data = res -- overwrite
   assert(ZEN.OK)
   TMP.valid = true
   ZEN:ftrace("validation passed for "..name.. " with schema "..schema)
end

function ZEN:validate_recur(obj, name)
   ZEN.assert(name, "ZEN:validate_recur error: schema name is nil")
   ZEN.assert(obj, "ZEN:validate_recur error: object is nil")
   local s = ZEN.schemas[name]
   ZEN.assert(s, "ZEN:validate_recur error: schema not found: "..name)
   ZEN.assert(type(s) == 'function', "ZEN:validate_recur error: schema is not a function: "..name)
   ZEN:ftrace("validate_recur "..name)
   local res = s(obj)
   ZEN.assert(res, "Schema validation failed: "..name)
   return(res)
end

function ZEN:ack_table(key,val)
   ZEN.assert(TMP.valid, "No valid object found in TMP")
   ZEN.assert(type(key) == 'string',"ZEN:table_add arg #1 is not a string")
   ZEN.assert(type(val) == 'string',"ZEN:table_add arg #2 is not a string")
   if not ACK[key] then ACK[key] = { } end
   ACK[key][val] = TMP.data
end

---
-- Final step inside the <b>Given</b> block towards the <b>When</b>:
-- pass on a data structure into the ACK memory space, ready for
-- processing.  It requires the data to be present in TMP[name] and
-- typically follows a @{pick}. In some restricted cases it is used
-- inside a <b>When</b> block following the inline insertion of data
-- from zencode.
--
-- @function ZEN:ack(name)
-- @param name string key of the data object in TMP[name]
function ZEN:ack(name)
   ZEN.assert(TMP.data and TMP.valid, "No valid object found: ".. name)
   assert(ZEN.OK)
   local t = type(ACK[name])
   if not ACK[name] then -- assign in ACK the single object
	  ACK[name] = TMP.data
	  goto done
   end
   -- ACK[name] already holds an object
   -- not a table?
   if t ~= 'table' then -- convert single object to array
	  ACK[name] = { ACK[name] }
	  table.insert(ACK[name], TMP.data)
	  goto done
   end
   -- it is a table already
   if isarray(ACK[name]) then -- plain array
	  table.insert(ACK[name], TMP.data)
	  goto done
   else -- associative map
	  table.insert(ACK[name], TMP.data) -- TODO: associative map insertion
	  goto done
   end
   ::done::
   assert(ZEN.OK)
end

function ZEN:ackmy(name, object)
   local obj = object or TMP.data
   ZEN:trace("f   pushmy() "..name.." "..type(obj))
   ZEN.assert(WHO, "No identity specified")
   ZEN.assert(obj, "Object not found: ".. name)
   local me = WHO
   if not ACK[me] then ACK[me] = { } end
   ACK[me][name] = obj
   assert(ZEN.OK)
end

--- When block (ACK read-write memory)
-- @section When

---
-- Draft a new text made of a simple string: convert it to @{OCTET}
-- and append it to ACK.draft.
--
-- @function ZEN:draft(string)
-- @param string any string to be appended as draft
function ZEN:draft(s)
   if s then
	  ZEN.assert(type(s) == "string", "Provided draft is not a string")
	  if not ACK.draft then
		 ACK.draft = str(s)
	  else
		 ACK.draft = ACK.draft .. str(s)
	  end
   else -- no arg: sanity checks
	  ZEN.assert(ACK.draft, "No draft found in ACK.draft")
   end
   assert(ZEN.OK)
end


---
-- Compare equality of two data objects (TODO: octet, ECP, etc.)
-- @function ZEN:eq(first, second)

---
-- Check that the first object is greater than the second (TODO)
-- @function ZEN:gt(first, second)

---
-- Check that the first object is lesser than the second (TODO)
-- @function ZEN:lt(first, second)


--- Then block (OUT write-only memory)
-- @section Then

---
-- Move a generic data structure from ACK to OUT memory space, ready
-- for its final JSON encoding and print out.
-- @function ZEN:out(name)

---
-- Move 'my own' data structure from ACK to OUT.whoami memory space,
-- ready for its final JSON encoding and print out.
-- @function ZEN:outmy(name)

---
-- Convert a data object to the desired format (argument name provided
-- as string), or use CONF.encoding when called without argument
--
-- @function ZEN:export(object, format)
-- @param object data element to be converted
-- @param format pointer to a converter function
-- @return object converted to format
function ZEN:export(object, format)
   -- CONF { encoding = <function 1>,
   --        encoding_prefix = "u64"  }
   ZEN.assert(object, "ZEN:export object not found")
   ZEN.assert(iszen(type(object)), "ZEN:export called on a ".. type(object))
   local conv_f = nil
   local ft = type(format)
   if format and ft == 'function' then conv_f = format goto ok end
   if format and ft == 'string' then conv_f = get_encoding(format).fun goto ok end
   conv_f = CONF.output.encoding.fun -- fallback to configured conversion function
   ::ok::
   ZEN.assert(type(conv_f) == 'function' , "ZEN:export conversion function not configured")
   return conv_f(object) -- TODO: protected call
end

---
-- Import a generic data element from the tagged format, or use
-- CONF.encoding
--
-- @function ZEN:import(object)
-- @param object data element to be read
-- @param secured block implicit conversion from untagget string
-- @return object read
function ZEN:import(object, secured)
   ZEN.assert(object, "ZEN:import object is nil")
   local t = type(object)
   if iszen(t) then
	  warn("ZEN:import object already converted to "..t)
	  return t
   end
   ZEN.assert(t ~= 'table', "ZEN:import table is impossible: object needs to be 'valid'")
   ZEN.assert(t == 'string', "ZEN:import object is not a string: "..t)
   -- OK, convert
   if string.sub(object,1,3) == 'u64' and O.is_url64(object) then
	  -- return decoded string format for JSON.decode
	  return O.from_url64(object)
   elseif string.sub(object,1,3) == 'b64' and O.is_base64(object) then
	  -- return decoded string format for JSON.decode
	  return O.from_base64(object)
   elseif string.sub(object,1,3) == 'hex' and O.is_hex(object) then
	  -- return decoded string format for JSON.decode
	  return O.from_hex(object)
   elseif string.sub(object,1,3) == 'bin' and O.is_bin(object) then
	  -- return decoded string format for JSON.decode
	  return O.from_bin(object)
   -- elseif CONF.input.encoding.fun then
   -- 	  return CONF.input.encoding.fun(object)
   elseif string.sub(object,1,3) == 'str' then
	  return O.from_string(object)
   end
   if not secured then
	  ZEN:wtrace("import implicit conversion from string ("..#object.." bytes)")
	  return O.from_string(object)
   end
   error("Import secured to fail on untagged object",1)
   return nil
   -- error("ZEN:import failed conversion from "..t, 3)
end



