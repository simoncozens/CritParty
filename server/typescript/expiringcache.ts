class ExpiringCache<T> {

  private values: Map<string, T> = new Map<string, T>();
  private lastused: Map<string, number> = new Map<string, number>();
  private expiry: number = 60 * 60 * 24;

  public _values (): Map<string, T> {
    return this.values;
  }

  public get(key: string): T {
    const hasKey = this.values.has(key);
    let entry: T;
    if (hasKey) {
      entry = this.values.get(key);
      this.lastused.set(key, (new Date()).getTime()/1000);
    }
    this.clean()
    return entry;
  }

  public put(key: string, value: T) {
    this.values.set(key, value);
    this.lastused.set(key, (new Date()).getTime()/1000);
    this.clean();
  }

  public delete(key: string) {
    this.values.delete(key);
    this.lastused.delete(key);
  }

  private clean() {
    this.lastused.forEach( (time, key) => {
      if ((new Date()).getTime()/1000 - time > this.expiry) {
        this.delete(key);
      }
    })
  }
}
export { ExpiringCache };