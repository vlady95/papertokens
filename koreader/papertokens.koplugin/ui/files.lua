-- ui/files.lua — acceso a disco. DESECHABLE y dependiente del entorno.
--
-- Todo lo que toca el sistema de archivos vive AQUÍ y en ningún otro lado,
-- para que core/ siga siendo puro y probable en la Mac.
--
-- ⚠ PENDIENTE DE VERIFICAR EN EL DEVICE (el Kindle estaba desconectado al
-- escribir esto). Son las dos únicas llamadas del plugin que no se
-- comprobaron contra la instalación real:
--   1. require("libs/libkoreader-lfs") — el LuaFileSystem que KOReader trae
--      empaquetado, para listar el directorio.
--   2. require("datastorage"):getSettingsDir() — dónde guardar el registro
--      de uso. datastorage.lua sí se verificó que existe en la raíz de
--      koreader/; lo que falta confirmar es el nombre del método.
-- Ambas van envueltas en pcall: si alguna falla, el plugin lo dice en la
-- biblioteca en vez de reventar, y hay respaldo para la segunda.

local M = {}

local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")

-- Sube n niveles de una ruta.
local function parent(path, n)
  for _ = 1, n do
    path = path:match("^(.*)/[^/]+$") or path
  end
  return path
end

-- Carpeta de mazos: hermana de koreader/ en la raíz de la partición, para
-- que sea trivial de encontrar al montar el Kindle por USB.
--   .../koreader/plugins/papertokens.koplugin  →  .../papertokens
function M.decks_dir(plugin_dir, folder_name)
  return parent(plugin_dir, 3) .. "/" .. (folder_name or "papertokens")
end

function M.archive_dir(decks_dir, sub)
  return decks_dir .. "/" .. (sub or "archivados")
end

function M.exists(path)
  if lfs_ok then
    return lfs.attributes(path, "mode") ~= nil
  end
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function M.mkdir(path)
  if lfs_ok then pcall(lfs.mkdir, path) end
  return M.exists(path)
end

-- Lista los .txt de un directorio, ordenados. Devuelve rutas, o nil y el
-- motivo si el directorio no se puede recorrer.
function M.list_txt(dir)
  if not lfs_ok then
    return nil, "no se pudo cargar libkoreader-lfs"
  end
  if lfs.attributes(dir, "mode") ~= "directory" then
    return nil, "no existe la carpeta " .. dir
  end
  local out = {}
  local ok, err = pcall(function()
    for entry in lfs.dir(dir) do
      if entry ~= "." and entry ~= ".."
         and entry:lower():match("%.txt$")
         and lfs.attributes(dir .. "/" .. entry, "mode") == "file" then
        out[#out + 1] = dir .. "/" .. entry
      end
    end
  end)
  if not ok then return nil, tostring(err) end
  table.sort(out)
  return out
end

function M.read(path)
  local f = io.open(path, "rb")
  if not f then return nil, "no se pudo abrir" end
  local text = f:read("*a")
  f:close()
  return text
end

function M.write(path, text)
  local f = io.open(path, "wb")
  if not f then return false, "no se pudo escribir " .. path end
  f:write(text)
  f:close()
  return true
end

function M.remove(path)
  return os.remove(path)
end

-- Archivar = mover a la subcarpeta. Reversible, cuesta una línea.
function M.move_to(path, dest_dir)
  M.mkdir(dest_dir)
  local name = path:match("([^/]+)$")
  return os.rename(path, dest_dir .. "/" .. name)
end

-- Ruta del registro de uso. Va APARTE de los .txt: si viviera junto a
-- ellos, copiar o borrar mazos por USB se lo llevaría.
function M.registry_path(plugin_dir)
  local ok, dir = pcall(function()
    return require("datastorage"):getSettingsDir()
  end)
  if ok and type(dir) == "string" and dir ~= "" then
    return dir .. "/papertokens_uso.txt"
  end
  -- respaldo: junto a koreader/, fuera de la carpeta de mazos
  return parent(plugin_dir, 2) .. "/papertokens_uso.txt"
end

M.parent = parent
M.lfs_available = lfs_ok

return M
