--
-- (C) 2013-20 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"
local page_utils = require("page_utils")
local alert_consts = require("alert_consts")
local rtt_utils = require("rtt_utils")
local plugins_utils = require("plugins_utils")
local template = require("template_utils")
require("graph_utils")
require("alert_utils")

local ts_creation = plugins_utils.timeseriesCreationEnabled()

if not isAllowedSystemInterface() then
   return
end

sendHTTPContentTypeHeader('text/html')

page_utils.set_active_menu_entry(page_utils.menu_entries.rtt_monitor)

dofile(dirs.installdir .. "/scripts/lua/inc/menu.lua")

local page = _GET["page"] or "overview"
local host = _GET["rtt_host"]
local base_url = plugins_utils.getUrl("rtt_stats.lua") .. "?ifid=" .. getInterfaceId(ifname)
local url = base_url

if not isEmptyString(host) then
  url = url .. "&rtt_host=" .. host
end

local title = i18n("graphs.rtt")

if((host ~= nil) and (page ~= "overview")) then
   title = title..": " .. rtt_utils.key2label(host)
end


page_utils.print_navbar(title, url,
			{
			   {
			      active = page == "overview" or not page,
			      page_name = "overview",
			      label = "<i class=\"fas fa-lg fa-home\"></i>",
			      url = base_url,
			   },
			   {
			      hidden = not host or not ts_creation,
			      active = page == "historical",
			      page_name = "historical",
			      label = "<i class='fas fa-lg fa-chart-area'></i>",
			   },
			   {
			      hidden = not isAdministrator() or not plugins_utils.hasAlerts(getSystemInterfaceId(), {entity = alert_consts.alertEntity("pinged_host")}),
			      active = page == "alerts",
			      page_name = "alerts",
			      label = "<i class=\"fas fa-lg fa-exclamation-triangle\"></i>",
			   },
			}
)

-- #######################################################

if(page == "overview") then

  if isAdministrator() then

    if(_POST["rtt_hosts"] ~= nil) then
      local rtt_hosts_args = string.split(_POST["rtt_hosts"], ",") or {_POST["rtt_hosts"]}
      local rtt_hosts = {}

      -- process arguments
      for _, host_line in pairs(rtt_hosts_args) do
        local parts = string.split(host_line, "|")
        local key = table.remove(parts, 1)
        local old_host = table.remove(parts, 1)
        local value = table.concat(parts, "|")

        rtt_hosts[key] = {old_host, value}
      end

      -- Delete changed
      for host, value in pairs(rtt_hosts) do
        local old_host = value[1]

        if((not isEmptyString(old_host)) and (host ~= old_host)) then
          rtt_utils.removeHost(old_host)
        end
      end

      -- Add new
      for host, value in pairs(rtt_hosts) do
        local conf = value[2]
        rtt_utils.addHost(host, conf)
      end

    elseif((_POST["action"] == "delete") and (_POST["rtt_host"] ~= nil)) then
        rtt_utils.removeHost(_POST["rtt_host"])
    end
  end

  print([[
    <div class='container-fluid my-3'>
      <div class='row'>
        <div class='col-md-12 col-12'>
          <table class="table w-100 table-striped table-hover table-bordered" id="rtt-table">
            <thead>
              <tr>
                <th>]].. i18n("flow_details.url") ..[[</th>
                <th>]].. i18n("chart") ..[[</th>
                <th>Threshold</th>
                <th>Last Measurement</th>
                <th>Last IP</th>
                <th>Measurement Time</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div id='rtt-edit-modal' class="modal fade" tabindex="-1" role="dialog">
      <form method="post" id='rtt-edit-form'>
        <div class="modal-dialog modal-lg modal-dialog-centered" role="document">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Edit RTT Record</h5>
              <button type="button" class="close" data-dismiss="modal" aria-label="Close">
                <span aria-hidden="true">&times;</span>
              </button>
            </div>
            <div class="modal-body container-fluid">
              <div class="form-group row">
                <label class="col-sm-2 col-form-label">Measurument</label>
                <div class="col-sm-5">
                  ]]..
                  generate_select("select-measurement", "measurement", true, false, {
                    { value = "icmp",   title = "Icmp"},
                    { value = "icmp6",  title = "Icmp6"},
                    { value = "ipv4",   title = "IpV4"},
                    { value = "ipv6",   title = "IpV6"},
                  })
                  ..[[
                </div>
              </div>
              <div class="form-group row">
                <label class="col-sm-2 col-form-label">Host</label>
                <div class="col-sm-5">
                  <input required id="host-input" type="text" name="host" class="form-control" />
                </div>
              </div>
              <div class="form-group row">
                <label class="col-sm-2 col-form-label">Threshold</label>
                <div class="col-sm-5">
                  <div class="input-group">
                    <div class="input-group-prepend">
                      <span class="input-group-text">&gt;</span>
                    </div>
                    <input required id="threshold" name="threshold" type="number" class="form-control" min="1">
                    <span class="my-auto ml-1">msec</span>
                  </div>
                </div>
              </div>
              <span class="invalid-feedback"></span>
            </div>
            <div class="modal-footer">
              <button id="btn-reset-defaults" type="button" class="btn btn-danger mr-auto">Reset Default</button>
              <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
              <button type="submit" class="btn btn-primary">Apply</button>
            </div>
          </div>
        </div>
      </form>
    </div>

    <div id='rtt-delete-modal' class="modal" tabindex="-1" role="dialog">
      <form id='rtt-delete-form'>
        <div class="modal-dialog modal-dialog-centered" role="document">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Delete: </h5>
              <button type="button" class="close" data-dismiss="modal" aria-label="Close">
                <span aria-hidden="true">&times;</span>
              </button>
            </div>
            <div class="modal-body">
              <p>
                Do you want really remove this record?
              </p>
            </div>
            <div class="modal-footer">
              <button type="button" class="btn btn-secondary" data-dismiss="modal">Cancel</button>
              <button type="submit" class="btn btn-danger">Confirm Deleting</button>
            </div>
          </div>
        </div>
      </form>
    </div>

  ]])

  print([[
    <link href="]].. ntop.getHttpPrefix() ..[[/datatables/datatables.min.css" rel="stylesheet"/>
    <script type='text/javascript' src=']].. ntop.getHttpPrefix() ..[[/js/rtt/rtt-utils.js'></script>
  ]])


elseif((page == "historical") and (host ~= nil)) then

  local schema = _GET["ts_schema"] or "monitored_host:rtt"
  local selected_epoch = _GET["epoch"] or ""
  local tags = {ifid=getSystemInterfaceId(), host=host}
  url = url.."&page=historical&rtt_host=" .. host

  local rtt_host = rtt_utils.getHost(host)
  local timeseries = {
    { schema="monitored_host:rtt", label=i18n("graphs.num_ms_rtt") },
  }

  if(rtt_host and (rtt_host.probetype == "http_get")) then
    timeseries = table.merge(timeseries, {
      { schema="monitored_host:http_stats", label=i18n("graphs.http_stats"), metrics_labels = { i18n("graphs.name_lookup"), i18n("graphs.app_connect"), i18n("other") }},
    })
  end

  drawGraphs(getSystemInterfaceId(), schema, tags, _GET["zoom"], url, selected_epoch, {
    timeseries = timeseries,
  })

elseif((page == "alerts") and isAdministrator()) then

   local old_ifname = ifname
   local ts_utils = require("ts_utils")
   local influxdb = ts_utils.getQueryDriver()
   interface.select(getSystemInterfaceId())

   _GET["ifid"] = getSystemInterfaceId()
   _GET["entity"] = alert_consts.alertEntity("pinged_host")
   _GET["entity_val"] = _GET["rtt_host"]

   drawAlerts()

   interface.select(old_ifname)
end

-- #######################################################

dofile(dirs.installdir .. "/scripts/lua/inc/footer.lua")