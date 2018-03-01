const fs = require('fs')
// you have to copy the js.mem file in the CWD as per design or --memory-init-file 0
// but it is not recommended as stated in https://github.com/kripken/emscripten/issues/2537
fs.writeFileSync('zenroom.js.mem', fs.readFileSync('../src/zenroom.js.mem'));

const zenroom_module = require('../src/zenroom.js')

const zenroom = (script_file, conf_file=null, keys_file=null, data_file=null, verbosity=3) => {
  process.stderr._write = function(chunk, encoding, callback) { callback() }
  const enc = { encoding: 'utf8' }
  const script = fs.readFileSync(script_file, enc)
  const conf = (conf_file) ? fs.readFileSync(conf_file, env) : null
  const keys = (keys_file) ? fs.readFileSync(keys_file, env) : null
  const data = (data_file) ? fs.readFileSync(data_file, env) : null

  return zenroom_module.ccall('zenroom_exec', 'number',
                              ['string', 'string', 'string', 'string', 'number'],
                              [script, conf, keys, data, verbosity])
}

zenroom('./keygen.lua')
