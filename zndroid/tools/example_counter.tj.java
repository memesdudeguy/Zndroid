class Counter {
    int value;
    int limit;

    void increment() {
        value = value + 1;
    }

    int isMax() {
        if (value >= limit) {
            return 1;
        }
        return 0;
    }

    int sumUpTo() {
        int i;
        int sum;
        i = 0;
        sum = 0;
        while (i < value) {
            sum = sum + i;
            i = i + 1;
        }
        return sum;
    }
}
