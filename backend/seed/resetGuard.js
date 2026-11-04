const RESET_FLAG = '--reset';
const CONFIRM_FLAG = '--confirm-wipe-shared-data';

function parseResetArgs(argv) {
  const wantsReset = argv.includes(RESET_FLAG);
  const confirmed = argv.includes(CONFIRM_FLAG);
  return { reset: wantsReset && confirmed, blocked: wantsReset && !confirmed };
}

module.exports = { parseResetArgs, RESET_FLAG, CONFIRM_FLAG };
