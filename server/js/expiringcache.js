"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class ExpiringCache {
    constructor() {
        this.values = new Map();
        this.lastused = new Map();
        this.expiry = 60 * 60 * 24;
    }
    get(key) {
        const hasKey = this.values.has(key);
        let entry;
        if (hasKey) {
            entry = this.values.get(key);
            this.lastused.set(key, (new Date()).getTime() / 1000);
        }
        this.clean();
        return entry;
    }
    put(key, value) {
        this.values.set(key, value);
        this.lastused.set(key, (new Date()).getTime() / 1000);
        this.clean();
    }
    delete(key) {
        this.values.delete(key);
        this.lastused.delete(key);
    }
    clean() {
        this.lastused.forEach((time, key) => {
            if ((new Date()).getTime() / 1000 - time > this.expiry) {
                this.delete(key);
            }
        });
    }
}
exports.ExpiringCache = ExpiringCache;
//# sourceMappingURL=expiringcache.js.map