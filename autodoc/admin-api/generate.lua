#!/usr/bin/env resty

setmetatable(_G, nil)

local lfs = require("lfs")
local cjson = require("cjson")
local general = require("autodoc.admin-api.general")

local method_array = {
  "POST",
  "HEAD",
  "GET",
  "PATCH",
  "PUT",
  "DELETE",
  "OPTIONS",
}

-- Chicago-style prepositions to be lowercased,
-- based on https://capitalizemytitle.com/
for _, p in ipairs({
  "about",
  "above",
  "across",
  "after",
  "against",
  "along",
  "among",
  "around",
  "at",
  "before",
  "behind",
  "below",
  "beneath",
  "beside",
  "beyond",
  "by",
  "down",
  "during",
  "for",
  "from",
  "in",
  "inside",
  "into",
  "near",
  "of",
  "off",
  "on",
  "out",
  "outside",
  "over",
  "past",
  "through",
  "throughout",
  "to",
  "toward",
  "under",
}) do
  general.title_exceptions[p] = p
end

local utils = {
  -- "EXAMPLE of teXT using dns" => "Example of Text Using DNS".
  titleize = function(str)
    local text = str:gsub("(%a[%w_'-]*)", function(word)
      local exception = general.title_exceptions[word:lower()]
      if exception then
        return exception
      else
        return word:sub(1,1):upper()..word:sub(2):lower()
      end
    end)
    -- force very first character uppercase
    return text:sub(1,1):upper()..text:sub(2)
  end
}

local KONG_PATH = os.getenv("KONG_PATH") or "."

package.path = KONG_PATH .. "/?.lua;" .. KONG_PATH .. "/?/init.lua;" .. package.path

local pok, kong_meta = pcall(require, "kong.meta") -- luacheck: ignore
if not pok then
  error("failed loading Kong modules. please set the KONG_PATH environment variable.")
end

local admin_api_data = require("autodoc.admin-api.data.admin-api")

local Endpoints = require("kong.api.endpoints")

-- Minimal boilerplate so that module files can be loaded
_KONG = require("kong.meta")          -- luacheck: ignore
kong = require("kong.global").new()   -- luacheck: ignore
kong.configuration = {                -- luacheck: ignore
  loaded_plugins = {},
  loaded_vaults = {},
}
kong.db = require("kong.db").new({    -- luacheck: ignore
  database = "postgres",
})
kong.configuration = { -- luacheck: ignore
  loaded_plugins = {},
  loaded_vaults = {},
}

--------------------------------------------------------------------------------

local function sortedpairs(tbl)
  local keys = {}
  for key, _ in pairs(tbl) do
    table.insert(keys, key)
  end
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    local k = keys[i]
    return k, tbl[k]
  end
end

local function render(template, subs)
  subs = setmetatable(subs, { __index = function(_, k)
    error("failed applying autodoc template: no variable ${" .. k .. "}")
  end })
  return (template:gsub("${([^}]+)}", subs))
end

local function get_or_create(tbl, key)
  local v = tbl[key]
  if not v then
    v = {}
    tbl[key] = v
  end
  return v
end

local function to_singular(plural)
  return plural:gsub("s$", "")
end

local function entity_to_api_path(entity)
  return "kong/api/routes/" .. entity .. ".lua"
end

local function entity_to_schema_path(entity)
  return "kong/db/schema/entities/" .. entity .. ".lua"
end

local function cjson_encode(value)
  return (cjson.encode(value):gsub("\\/", "/"):gsub(",", ", "))
end

-- A deterministic pseudo-UUID generator, to make autodoc idempotent.
local gen_uuid
local reset_uuid
do
  local uuids = {
    "9748f662-7711-4a90-8186-dc02f10eb0f5",
    "4e3ad2e4-0bc4-4638-8e34-c84a417ba39b",
    "a5fb8d9b-a99d-40e9-9d35-72d42a62d83a",
    "51e77dc2-8f3e-4afa-9d0e-0e3bbbcfd515",
    "fc73f2af-890d-4f9b-8363-af8945001f7f",
    "4506673d-c825-444c-a25b-602e3c2ec16e",
    "d35165e2-d03e-461a-bdeb-dad0a112abfe",
    "af8330d3-dbdc-48bd-b1be-55b98608834b",
    "a9daa3ba-8186-4a0d-96e8-00d80ce7240b",
    "127dfc88-ed57-45bf-b77a-a9d3a152ad31",
    "9aa116fd-ef4a-4efa-89bf-a0b17c4be982",
    "ba641b07-e74a-430a-ab46-94b61e5ea66b",
    "ec1a1f6f-2aa4-4e58-93ff-b56368f19b27",
    "a4407883-c166-43fd-80ca-3ca035b0cdb7",
    "01c23299-839c-49a5-a6d5-8864c09184af",
    "ce44eef5-41ed-47f6-baab-f725cecf98c7",
    "02621eee-8309-4bf6-b36b-a82017a5393e",
    "66c7b5c4-4aaf-4119-af1e-ee3ad75d0af4",
    "7fca84d6-7d37-4a74-a7b0-93e576089a41",
    "d044b7d4-3dc2-4bbc-8e9f-6b7a69416df6",
    "a9b2107f-a214-47b3-add4-46b942187924",
    "04fbeacf-a9f1-4a5d-ae4a-b0407445db3f",
    "43429efd-b3a5-4048-94cb-5cc4029909bb",
    "d26761d5-83a4-4f24-ac6c-cff276f2b79c",
    "91020192-062d-416f-a275-9addeeaffaf2",
    "a2e013e8-7623-4494-a347-6d29108ff68b",
    "147f5ef0-1ed6-4711-b77f-489262f8bff7",
    "a3ad71a8-6685-4b03-a101-980a953544f6",
    "b87eb55d-69a1-41d2-8653-8d706eecefc0",
    "4e8d95d4-40f2-4818-adcb-30e00c349618",
    "58c8ccbb-eafb-4566-991f-2ed4f678fa70",
    "ea29aaa3-3b2d-488c-b90c-56df8e0dd8c6",
    "4fe14415-73d5-4f00-9fbc-c72a0fccfcb2",
    "a3395f66-2af6-4c79-bea2-1b6933764f80",
    "885a0392-ef1b-4de3-aacf-af3f1697ce2c",
    "f5a9c0ca-bdbb-490f-8928-2ca95836239a",
    "173a6cee-90d1-40a7-89cf-0329eca780a6",
    "bdab0e47-4e37-4f0b-8fd0-87d95cc4addc",
    "f00c6da4-3679-4b44-b9fb-36a19bd3ae83",
    "0c61e164-6171-4837-8836-8f5298726d53",
    "5027BBC1-508C-41F8-87F2-AB1801E9D5C3",
    "68FDB05B-7B08-47E9-9727-AF7F897CFF1A",
    "B2A30E8F-C542-49CF-8015-FB674987D1A5",
    "518BBE43-2454-4559-99B0-8E7D1CD3E8C8",
    "7C4747E9-E831-4ED8-9377-83A6F8A37603",
  }

  local ctr = 0

  gen_uuid = function()
    ctr = ctr + 1
    return assert(uuids[ctr])
  end

  reset_uuid = function()
    ctr = 0
  end
end

--------------------------------------------------------------------------------
-- Unindent a multi-line string for proper indenting in
-- square brackets.
--
-- Ex:
--   unindent([[
--       hello world
--       foo bar
--   ]])
--
-- will return: "hello world\nfoo bar"
local function unindent(str)
  local min = 2^31
  local lines = {}
  str = (str:sub(-1) == "\n") and str or (str .. "\n")
  for line in str:gmatch("([^\n]*)\n") do
    local nonblank = line:match("()[^%s]")
    if nonblank and nonblank < min then
      min = nonblank
    end
    table.insert(lines, line)
  end
  for i, line in ipairs(lines) do
    lines[i] = line:sub(min)
  end
  return table.concat(lines, "\n")
end

local function each_field(fields)
  local i = 0
  return function()
    i = i + 1
    local f = fields[i]
    if f then
      local k = next(f)
      local v = f[k]
      return k, v
    end
  end
end

--------------------------------------------------------------------------------

local function assert_data(value, description)
  if value == nil then
    error("\n\n" ..
          "****************************************\n" ..
          "Missing " .. description .. "\n" ..
          "-- please document it in autodoc/data/admin-api.lua\n" ..
          "****************************************\n", 2)
  end

  return value
end

--------------------------------------------------------------------------------

local function gen_kind(finfo, field_data)
  if field_data.kind then
    return "<br>*"  .. field_data.kind .. "*"
  elseif finfo.required ~= true then
    return "<br>*optional*"
  else
    return ""
  end
end

local function break_long_code_block(code, separator, max_row_len)
  local escaped_separator = separator == "." and "%." or separator
  local word_break_separator = separator .. "`<wbr>`"
  local buffer = { "`" }
  local row_len = 0
  local first = true
  for part in code:gmatch("[^" .. escaped_separator .."]+") do
    local part_len = #part
    if not first then
      if row_len + part_len + 1 < max_row_len then
        buffer[#buffer + 1] = separator
        row_len = row_len + 1
      else
        buffer[#buffer + 1] = word_break_separator
        row_len = 0
      end
    end
    buffer[#buffer + 1] = part
    row_len = row_len + part_len
    first = false
  end
  buffer[#buffer + 1] = "`"

  return table.concat(buffer)
end

local function gen_field_info(finfo)
  local out = {}

  if finfo.one_of then
    local vals = {}
    for _, f in ipairs(finfo.one_of) do
      local v = type(f) == "string" and ("%q"):format(f) or tostring(f)
      table.insert(vals, "`" .. v .. "`")
    end
    table.insert(out, " Accepted values are: " .. table.concat(vals, ", ") .. ". ")
  end

  if finfo.default then
    local json = cjson_encode(finfo.default)
    local default = break_long_code_block(json, ",", 30)
    table.insert(out, " Default: " ..  default .. ".")
  end

  return table.concat(out)
end

local function gen_notation(fname, finfo, field_data)
  if finfo.type == "array" then
    local form_example = {}
    local example = field_data.examples
                    and (field_data.examples[1] or field_data.examples[2])
                    or field_data.example
    for i, item in ipairs(example or finfo.default) do
      table.insert(form_example, fname .. "[]=" .. item)
      if i == 2 then
        break
      end
    end
    return [[ With form-encoded, the notation is `]] ..
           table.concat(form_example, "&") ..
           [[`. With JSON, use an Array.]]
  elseif finfo.type == "foreign" then
    local fschema = assert(require("kong.db.schema.entities." .. finfo.reference))
    local ek = fschema.endpoint_key
    if ek then
      return ([[With form-encoded, the notation is ]] ..
              [[`$FNAME.id=<$FNAME id>` or ]] ..
              [[`$FNAME.$ENDPOINT_KEY=<$FNAME $ENDPOINT_KEY>`. ]] ..
              [[With JSON, use "]] ..
              [[`"$FNAME":{"id":"<$FNAME id>"}` or ]] ..
              [[`"$FNAME":{"$ENDPOINT_KEY":"<$FNAME $ENDPOINT_KEY>"}`.]]):
              gsub("$([A-Z_]*)", {
                FNAME = fname,
                ENDPOINT_KEY = ek,
              })
    else
      return ([[With form-encoded, the notation is ]] ..
              [[`$FNAME.id=<$FNAME id>`. ]] ..
              [[With JSON, use "]] ..
              [[`"$FNAME":{"id":"<$FNAME id>"}`.]]):
              gsub("$([A-Z_]*)", {
                FNAME = fname,
              })
    end
  else
    return ""
  end
end

local function write_field(outfd, fname, finfo, fullname, field_data, entity_name)
  local kind = gen_kind(finfo, field_data)
  local description = assert_data(field_data.description,
                                  "description for " .. entity_name .. "." .. fullname)
                      :gsub("%s+", " ")
  local field_info = gen_field_info(finfo)
  local notation = gen_notation(fname, finfo, field_data)

  fullname = break_long_code_block(fullname, ".", 25)

  outfd:write("    " .. fullname .. kind .. " | " .. description .. field_info .. notation .. "\n")
end

local function process_field(outfd, entity_data, entity_name, fname, finfo, prefix)
  local fullname = (prefix or "") .. fname
  local field_data = entity_data.fields[fullname]
  if not field_data then
    if finfo.type == "record" then
      for rfname, rfinfo in each_field(finfo.fields) do
        process_field(outfd, entity_data, entity_name, rfname, rfinfo, fullname .. ".")
      end
      return
    else
      error("Missing autodoc data for field " .. entity_name .. "." .. fullname)
    end
  end

  if field_data.skip then
    return
  end

  write_field(outfd, fname, finfo, fullname, field_data, entity_name)
end

local function gen_example(exn, entity, entity_data, fields, indent, prefix)
  local csv = {}
  for fname, finfo in each_field(fields) do
    local fullname = (prefix or "") .. fname

    local value
    local field_data = entity_data.fields[fullname]
    if finfo.type == "record" and not finfo.abstract then
      value = gen_example(exn, entity, entity_data, finfo.fields, indent .. "    ", fullname .. ".")
    elseif finfo.default ~= nil and field_data.examples == nil and field_data.example == nil then
      value = cjson_encode(finfo.default)
    else
      local example = field_data.examples and field_data.examples[exn]
      if example == nil then
        example = field_data.example
      end
      if example == nil then
        if finfo.uuid then
          example = gen_uuid()
        elseif finfo.type == "foreign" then
          example = { id = gen_uuid() }
        elseif finfo.timestamp then
          example = 1422386534
        elseif fname == "name" then
          example = "my-" .. to_singular(entity)
        end
      end
      if example ~= nil then
        value = cjson_encode(example)
      elseif not field_data.skip_in_example then
        error("missing example value for " .. entity .. "." .. fname)
      end
    end

    if value ~= nil then
      table.insert(csv, indent .. "    " .. '"' .. fname .. '": ' .. value)
    end
  end
  local out = {"{\n"}
  table.insert(out, table.concat(csv, ",\n"))
  table.insert(out, "\n")
  table.insert(out, indent .. "}")
  return table.concat(out)
end

local function write_entity_templates(outfd, entity, entity_data)
  local schema = assert(require("kong.db.schema.entities." .. entity))
  local singular = to_singular(entity)

  assert_data(entity_data.fields, "'fields' entry for " .. entity)

  outfd:write(singular .. "_body: |\n")
  outfd:write("    Attributes | Description\n")
  outfd:write("    ---:| ---\n")
  for fname, finfo in each_field(schema.fields) do
    process_field(outfd, entity_data, entity, fname, finfo)
  end

  if entity_data.extra_fields then
    for efname, efinfo in each_field(entity_data.extra_fields) do
      write_field(outfd, efname, efinfo, efname, efinfo, entity)
    end
  end

  outfd:write("\n")
  outfd:write(singular .. "_json: |\n")
  outfd:write("    " .. gen_example(1, entity, entity_data, schema.fields, "    ") .. "\n")
  outfd:write("\n")
  outfd:write(singular .. "_data: |\n")
  outfd:write('    "data": [' .. gen_example(1, entity, entity_data, schema.fields, "    ") .. ", ")
  outfd:write(gen_example(2, entity, entity_data, schema.fields, "    ") .. "],\n")
  outfd:write("\n")
end


local titles = {}

local function write_title(outfd, level, title, label)
  if not title then
    return
  end
  title = utils.titleize(title):gsub("^%s*", ""):gsub("%s*$", "")
  table.insert(titles, {
    level = level,
    title = title,
  })
  if label then
    label = "\n" .. label
  else
    label = ""
  end
  outfd:write((("#"):rep(level) .. " " .. title .. label .. "\n\n"))
end

local function section(outfd, title, content)
  if not content then
    return
  end
  write_title(outfd, 4, title)
  outfd:write(unindent(content) .. "\n")
  outfd:write("\n")
end

local function each_line(str)
 if str:sub(-1)~="\n" then
   str = str .. "\n"
 end
 return str:gmatch("(.-)\n")
end

local function blockquote(content)
  local buffer = {}
  for line in each_line(content) do
    buffer[#buffer + 1] = "> " .. line
  end
  return table.concat(buffer)
end

local function warning_message(outfd, content)
  outfd:write("\n\n{:.note}\n")
  outfd:write(blockquote(content))
  outfd:write("\n\n")
end

local function write_endpoint(outfd, endpoint, ep_data, dbless_methods)
  assert_data(ep_data, "data for endpoint " .. endpoint)
  if ep_data.done or ep_data.skip then
    return
  end

  -- check for endpoint-specific overrides (useful for db-less)
  for i, method in ipairs(method_array) do
    local meth_data = ep_data[method]
    if meth_data and meth_data.endpoint ~= false then
      assert_data(meth_data.title, "info for " .. method .. " " .. endpoint)
      if dbless_methods
        and not dbless_methods[method]
        and (not dbless_methods[endpoint]
             or not dbless_methods[endpoint][method])
      then
        write_title(outfd, 3, meth_data.title)
        warning_message(outfd, "**Note**: This API is not available in DB-less mode.")
      else
        write_title(outfd, 3, meth_data.title, "{:.badge .dbless}")
      end

      section(outfd, nil, meth_data.description)
      local fk_endpoints = meth_data.fk_endpoints or {}
      section(outfd, nil, meth_data.endpoint)
      for _, fk_endpoint in ipairs(fk_endpoints) do
        section(outfd, nil, fk_endpoint)
      end
      section(outfd, "Request Querystring Parameters", meth_data.request_query)
      section(outfd, "Request Body", meth_data.request_body)
      section(outfd, nil, meth_data.details)
      section(outfd, "Response", meth_data.response)
      outfd:write("---\n\n")
    end
  end
  ep_data.done = true
end

local function write_endpoints(outfd, info, all_endpoints, dbless_methods)
  for endpoint, ep_data in sortedpairs(info.data) do
    if endpoint:match("^/") then
      write_endpoint(outfd, endpoint, ep_data, dbless_methods)
      all_endpoints[endpoint] = ep_data
    end
  end
  return all_endpoints
end



local function write_general_section(outfd, filename, all_endpoints, name, data_general)
  local file_data = assert_data(data_general[name], "data for " .. filename)

  if file_data.skip == true then
    return
  end

  write_title(outfd, 2, file_data.title)

  assert_data(file_data.description,
              "'description' field for " .. filename)

  outfd:write(unindent(file_data.description))
  outfd:write("\n\n")

  local info = {
    filename = filename,
    data = file_data,
    mod = assert(loadfile(KONG_PATH .. "/" .. filename))()
  }

  write_endpoints(outfd, info, all_endpoints)

  return info
end

local active_verbs = {
  GET = "retrieve",
  POST = "create",
  PATCH = "update",
  PUT = "create or update",
  DELETE = "delete",
}

local passive_verbs = {
  GET = "retrieved",
  POST = "created",
  PATCH = "updated",
  PUT = "created or updated",
  DELETE = "deleted",
}

local function adjust_for_method(subs, method)
  subs.method = method:lower()
  subs.METHOD = method:upper()
  subs.active_verb = active_verbs[subs.METHOD]
  subs.passive_verb = passive_verbs[subs.METHOD]
  subs.Active_verb = utils.titleize(subs.active_verb)
  subs.Passive_verb = utils.titleize(subs.passive_verb)
end

local gen_endpoint
do
  local template_keys = {
    "title",
    "description",
    "details",
    "request_querystring",
    "request_body",
    "response",
    "endpoint",
  }

  gen_endpoint = function(edata, templates, subs, endpoint, method, has_ek)
    local ep_data = get_or_create(edata, endpoint)
    if ep_data.skip then
      return
    end
    local meth_data = get_or_create(ep_data, method)
    assert_data(templates, "templates definition for " .. endpoint)
    local meth_tpls = templates[method]
    assert_data(meth_tpls, "templates definition for " .. method .. " " .. endpoint)
    adjust_for_method(subs, method)

    for _, k in ipairs(template_keys) do
      local tk = (k == "endpoint")
                 and (has_ek and "endpoint_w_ek" or "endpoint")
                 or k
      local template = meth_tpls[tk] or templates[tk]
      if meth_data[k] == nil and ep_data[k] ~= nil then
        meth_data[k] = ep_data[k]
      end
      if meth_data[k] == nil and template then
        meth_data[k] = render(template, subs)
      end
    end
  end
end

local function gen_fk_endpoint(edata, templates, subs, parent_endpoint, method, has_ek, has_fek, nested)
  local ep_data = assert_data(edata[parent_endpoint],
                              "entity data for endpoint " .. parent_endpoint)

  local meth_data
  if nested then
    meth_data = ep_data[method]
    if not meth_data then
      return
    end
  else
    meth_data = assert(ep_data[method]) -- get_or_create(ep_data, method)
  end

  assert_data(templates, "templates definition for " .. parent_endpoint)
  local meth_tpls = templates[method]
  assert_data(meth_tpls, "templates definition for " .. method .. " " .. parent_endpoint)
  local tk
  if nested then
    if has_ek and has_fek then
      tk = "nested_endpoint_w_eks"
    elseif has_ek then
      tk = "nested_endpoint_w_ek"
    elseif has_fek then
      tk = "nested_endpoint_w_fek"
    else
      tk = "nested_endpoint"
    end

  else
    if has_ek then
      tk = "fk_endpoint_w_ek"
    elseif has_fek then
      tk = "fk_endpoint_w_fek"
    else
      tk = "fk_endpoint"
    end
  end

  local tpl = meth_tpls[tk] or templates[tk]
  assert_data(tpl, tk .. " template for " .. method .. " " .. parent_endpoint)
  adjust_for_method(subs, method)

  assert_data(meth_data.title, "'title' field for " .. method .. " " .. parent_endpoint)
  local fk_endpoints = get_or_create(meth_data, "fk_endpoints")
  table.insert(fk_endpoints, render(tpl, subs))
end


local function gen_template_subs_table(edata, plural, schema, fedata, fplural, fschema, fname)
  local api = edata.entity_url_collection_name or schema.admin_api_name or schema.name or plural
  local singular = to_singular(plural)
  local subs = {
    ["Entity"] = edata.entity_title or utils.titleize(singular),
    ["Entities"] = edata.entity_title_plural or utils.titleize(plural),
    ["entity"] = edata.entity_lower or singular:lower(),
    ["entities"] = edata.entity_lower_plural or plural:lower(),
    ["entities_url"] = api,
    ["entity_url"] = edata.entity_url_name or singular,
    ["endpoint_key"] = edata.entity_endpoint_key or schema.endpoint_key or "name",
  }
  if fedata then
    local fapi = fedata.entity_url_collection_name or fschema.admin_api_name or fschema.name or fplural
    local fsingular = to_singular(fplural)
    subs["ForeignEntity"] = fedata.entity_title or utils.titleize(fsingular)
    subs["ForeignEntities"] = fedata.entity_title_plural or utils.titleize(fplural)
    subs["foreign_entity"] = fedata.entity_lower or fsingular:lower()
    subs["foreign_entities"] = fedata.entity_lower_plural or fplural:lower()
    subs["foreign_entities_url"] = fapi
    subs["foreign_entity_url"] = fedata.entity_url_name or fname or fsingular
    subs["foreign_endpoint_key"] = fedata.entity_endpoint_key or fschema.endpoint_key or "name"
  end
  return subs
end

local function prepare_entity(data, entity_file, entity_data)
  local out = {}

  assert_data(entity_data.description,
              "'description' field for " .. entity_file)

  local schema = assert(loadfile(KONG_PATH .. "/" .. entity_to_schema_path(entity_file)))()
  local subs = gen_template_subs_table(entity_data, entity_file, schema)

  local title = entity_data.title or (subs.Entity .. " Object")

  table.insert(out, unindent(entity_data.description))

  if entity_data.fields.tags then
    table.insert(out, "\n")
    table.insert(out, unindent(render(data.entity_templates.tags, subs)))
  end

  table.insert(out, "\n\n")
  table.insert(out, "```json\n")
  table.insert(out, "{{ page." .. subs.entity .. "_json }}\n")
  table.insert(out, "```\n\n")

  if entity_data.details then
    table.insert(out, unindent(entity_data.details))
    table.insert(out, "\n\n")
  end

  local filename = "kong/api/routes/" .. entity_file .. ".lua"
  local modtbl = loadfile(KONG_PATH .. "/" .. filename)
  local mod = modtbl and modtbl() or {}

  local ename = schema.admin_api_name or schema.name
  local eapi = entity_data.admin_api_name or ename

  -- e.g. /services
  local collection_endpoint = "/" .. eapi
  gen_endpoint(entity_data, data.collection_templates, subs, collection_endpoint, "GET")
  gen_endpoint(entity_data, data.collection_templates, subs, collection_endpoint, "POST")

  -- e.g. /services/{name or id}
  local entity_endpoint = "/" .. eapi .. "/:" .. ename
  local has_ek = schema.endpoint_key ~= nil
  gen_endpoint(entity_data, data.entity_templates, subs, entity_endpoint, "GET", has_ek)
  gen_endpoint(entity_data, data.entity_templates, subs, entity_endpoint, "PUT", has_ek)
  gen_endpoint(entity_data, data.entity_templates, subs, entity_endpoint, "PATCH", has_ek)
  gen_endpoint(entity_data, data.entity_templates, subs, entity_endpoint, "DELETE", has_ek)

  return {
    filename = filename,
    entity = entity_file,
    schema = schema,
    title = title,
    intro = table.concat(out),
    data = entity_data,
    mod = mod,
  }
end

local function skip_fk_endpoint(edata, endpoint, method)
  local ret = edata
         and edata[endpoint]
         and ((edata[endpoint].endpoint == false)
              or (edata[endpoint][method] and edata[endpoint][method].endpoint == false))
  return ret
end

local function prepare_foreign_key_endpoints(data, entity_infos, entity)
  local einfo = entity_infos[entity]
  local edata = einfo.data

  for fname, finfo in each_field(einfo.schema.fields) do
    local foreigns = finfo.reference

    if finfo.type == "foreign" and not data.known.nodoc_entities[foreigns] then
      local feinfo = entity_infos[foreigns]
      local fedata = feinfo.data
      local subs = gen_template_subs_table(einfo.data, entity, einfo.schema, fedata, foreigns, feinfo.schema, fname)
      local has_ek = einfo.schema.endpoint_key ~= nil
      local has_fek = feinfo.schema.endpoint_key ~= nil

      local function gen_fk_endpoints(parent_endpoint, endpoint, meths, templates, srcdata, dstdata, nested)
        for _, method in ipairs(meths) do
          if not skip_fk_endpoint(edata, endpoint, method) then
            gen_fk_endpoint(dstdata, templates, subs, parent_endpoint, method, has_ek, has_fek, nested)
            local ep_data = get_or_create(srcdata, endpoint)
            ep_data.done = true
          end
        end
      end

      local ename  = einfo.schema.name
      local eapi   = einfo.schema.admin_api_name        or ename
      local enapi  = einfo.schema.admin_api_nested_name or eapi
      local fename = feinfo.schema.name
      local feapi  = feinfo.schema.admin_api_name       or fename

      -- e.g. /services/{service name or id}/routes
      gen_fk_endpoints(
        "/" .. eapi,
        "/" .. feapi .. "/:" .. fename .. "/" .. enapi,
        {"GET", "POST"},
        data.collection_templates,
        fedata, edata
      )

      -- e.g. /services/{service name or id}/routes/{route name or id}
      gen_fk_endpoints(
        "/" .. eapi .. "/:" .. ename,
        "/" .. feapi .. "/:" .. fename .. "/" .. enapi .. "/:" .. ename,
        {"GET", "PUT", "PATCH", "DELETE"},
        data.entity_templates,
        fedata, edata, true
      )

      -- e.g. /routes/{route name or id}/service
      gen_fk_endpoints(
        "/" .. feapi .. "/:" .. fename,
        "/" .. eapi .. "/:" .. ename .. "/" .. fname,
        {"GET", "PUT", "PATCH", "DELETE"},
        data.entity_templates,
        edata, fedata
      )

    end
  end

end

--------------------------------------------------------------------------------

-- Check that all modules present in the Admin API are known by this script.
local function check_admin_api_modules(data)
  local file_set = {}
  for _, item in ipairs(data.known.general_files) do
    file_set[item] = "use"
    data.known.general_files[item] = true
  end
  for _, item in ipairs(data.known.entities) do
    file_set[entity_to_api_path(item)] = "use"
    data.known.entities[item] = true
  end
  for _, item in ipairs(data.known.nodoc_entities) do
    file_set[entity_to_api_path(item)] = "nodoc"
    data.known.nodoc_entities[item] = true
  end
  for _, item in ipairs(data.known.nodoc_files) do
    file_set[item] = "nodoc"
    data.known.nodoc_files[item] = true
  end

  for file in lfs.dir(KONG_PATH .. "/kong/api/routes") do
    if file:match("%.lua$") then
      local name = "kong/api/routes/" .. file
      if not file_set[name] then
        error("File " .. name .. " not known to autodoc/admin-api/generate.lua! "  ..
              "Please add to the data.known tables.")
      end
    end
  end
end

local function check_endpoints(all_endpoints, infos)
  for _, info in ipairs(infos) do
    for endpoint, handler in pairs(info.mod) do
      if handler ~= Endpoints.not_found then
        assert_data(all_endpoints[endpoint],
                    "data for implemented endpoint " .. endpoint)
        assert_data(all_endpoints[endpoint].done or all_endpoints[endpoint].skip,
                    "done or skip mark in endpoint " .. endpoint)
      end
    end
  end
end

--------------------------------------------------------------------------------

local function write_admin_api(filename, data, title)
  lfs.mkdir("autodoc")
  lfs.mkdir("autodoc/output")
  lfs.mkdir("autodoc/output/admin-api")
  local outpath = "autodoc/output/admin-api/" .. filename

  local outfd = assert(io.open(outpath, "w+"))

  reset_uuid()

  outfd:write("---\n")
  outfd:write("#\n")
  outfd:write("#  WARNING: this file was auto-generated by a script.\n")
  outfd:write("#  DO NOT edit this file directly. Instead, send a pull request to change\n")
  outfd:write("#  https://github.com/Kong/kong/blob/master/autodoc/admin-api/data/admin-api.lua\n")
  outfd:write("#  or its associated files instead.\n")
  outfd:write("#\n")
  outfd:write("title: " .. utils.titleize(title) .. "\n")
  outfd:write("source_url: https://github.com/Kong/kong/blob/master/autodoc/admin-api/data/admin-api.lua\n")
  outfd:write("toc: false\n\n")
  for _, entity in ipairs(data.known.entities) do
    local entity_data = assert_data(data.entities[entity],
                                    "entity data for " .. entity)

    write_entity_templates(outfd, entity, entity_data)
  end
  outfd:write("\n---\n")

  for _, ipart in ipairs(assert_data(data.intro, "intro string")) do
    outfd:write("\n")
    write_title(outfd, 2, ipart.title)
    outfd:write(unindent(ipart.text))
    outfd:write("\n---\n\n")
  end

  local all_endpoints = {}

  local general_infos = {}

  for _, fullname in ipairs(data.known.general_files) do
    local name = fullname:match("/([^/]+)%.lua$")
    local ginfo = write_general_section(outfd, fullname, all_endpoints, name, data.general)
    table.insert(general_infos, ginfo)
    general_infos[name] = ginfo
  end

  local entity_infos = {}

  for _, entity in ipairs(data.known.entities) do
    local einfo = prepare_entity(data, entity, data.entities[entity])
    table.insert(entity_infos, einfo)
    entity_infos[entity] = einfo
  end

  for _, entity in ipairs(data.known.entities) do
    prepare_foreign_key_endpoints(data, entity_infos, entity)
  end

  for _, entity_info in ipairs(entity_infos) do
    write_title(outfd, 2, entity_info.title)
    outfd:write(entity_info.intro)
    write_endpoints(outfd, entity_info, all_endpoints, data.dbless_entities_methods)
  end

  -- Check that all endpoints were traversed
  check_endpoints(all_endpoints, entity_infos)
  check_endpoints(all_endpoints, general_infos)

  outfd:write(unindent(assert_data(data.footer, "footer string")))

  outfd:close()

  print("  Wrote " .. outpath)
end

--------------------------------------------------------------------------------

local function write_admin_api_nav(filename, data)
  lfs.mkdir("autodoc")
  lfs.mkdir("autodoc/output")
  lfs.mkdir("autodoc/output/nav")
  local outpath = "autodoc/output/nav/" .. filename

  local outfd = assert(io.open(outpath, "w+"))

  outfd:write(unindent(data.nav.header))

  local max_level = 3
  local level = 3
  for _, t in ipairs(titles) do
    if t.level <= max_level then
      if t.level <= level then
        outfd:write("\n")
      elseif t.level > level then
        outfd:write(("    "):rep(level - 1) .. "  items:\n")
      end
      level = t.level
      outfd:write(("    "):rep(level - 1) .. "- text: " .. t.title .. "\n")
      outfd:write(("    "):rep(level - 1) .. "  url: /admin-api/#" .. t.title:lower():gsub(" ", "-") .. "\n")
    end
  end

  outfd:close()

  print("  Wrote " .. outpath)
end

--------------------------------------------------------------------------------

local function main()
  print("Building Admin API docs...")

  check_admin_api_modules(admin_api_data)

  write_admin_api(
    "admin-api.md",
    admin_api_data,
    "Admin API"
  )

  write_admin_api_nav(
    "docs_nav.yml.admin-api.in",
    admin_api_data
  )
end

main()
