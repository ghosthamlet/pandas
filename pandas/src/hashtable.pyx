from khash cimport *
from cpython cimport PyString_Check, PyString_AsString


def test(ndarray arr, Py_ssize_t size_hint):
    cdef:
        kh_pymap_t *table
        int ret
        khiter_t k
        PyObject **data
        Py_ssize_t i, n
        ndarray[Py_ssize_t] indexer

    table = kh_init_pymap()
    kh_resize_pymap(table, size_hint)

    data = <PyObject**> arr.data
    n = len(arr)

    indexer = np.empty(n, dtype=np.int_)

    for i in range(n):
        k = kh_put_pymap(table, data[i], &ret)

        # if not ret:
        #     kh_del_pymap(table, k)

        table.vals[k] = i

    for i in range(n):
        k = kh_get_pymap(table, data[i])
        indexer[i] = table.vals[k]

    kh_destroy_pymap(table)

    return indexer


def test_str(ndarray arr, Py_ssize_t size_hint):
    cdef:
        kh_str_t *table
        kh_cstr_t val
        int ret
        khiter_t k
        PyObject **data
        Py_ssize_t i, n
        ndarray[Py_ssize_t] indexer

    table = kh_init_str()
    kh_resize_str(table, size_hint)

    data = <PyObject**> arr.data
    n = len(arr)

    indexer = np.empty(n, dtype=np.int_)

    for i in range(n):
        k = kh_put_str(table, PyString_AsString(<object> data[i]), &ret)

        # if not ret:
        #     kh_del_str(table, k)

        table.vals[k] = i

    # for i in range(n):
    #     k = kh_get_str(table, PyString_AsString(<object> data[i]))
    #     indexer[i] = table.vals[k]

    kh_destroy_str(table)

    return indexer

# def test2(ndarray[object] arr):
#     cdef:
#         dict table
#         object obj
#         Py_ssize_t i, loc, n
#         ndarray[Py_ssize_t] indexer

#     n = len(arr)
#     indexer = np.empty(n, dtype=np.int_)

#     table = {}
#     for i in range(n):
#         table[arr[i]] = i

#     for i in range(n):
#         indexer[i] =  table[arr[i]]

#     return indexer

def obj_unique(ndarray[object] arr):
    cdef:
        kh_pyset_t *table
        # PyObject *obj
        object obj
        PyObject **data
        int ret
        khiter_t k
        Py_ssize_t i, n
        list uniques

    n = len(arr)
    uniques = []

    table = kh_init_pyset()

    data = <PyObject**> arr.data

    # size hint
    kh_resize_pyset(table, n // 10)

    for i in range(n):
        obj = arr[i]

        k = kh_get_pyset(table, <PyObject*> obj)
        if not kh_exist_pyset(table, k):
            k = kh_put_pyset(table, <PyObject*> obj, &ret)
            # uniques.append(obj)
            # Py_INCREF(<object> obj)

    kh_destroy_pyset(table)

    return None

def int64_unique(ndarray[int64_t] arr):
    cdef:
        kh_int64_t *table
        # PyObject *obj
        int64_t obj
        PyObject **data
        int ret
        khiter_t k
        Py_ssize_t i, j, n
        ndarray[int64_t] uniques

    n = len(arr)
    uniques = np.empty(n, dtype='i8')

    table = kh_init_int64()
    kh_resize_int64(table, n)

    j = 0

    for i in range(n):
        obj = arr[i]

        k = kh_get_int64(table, obj)
        if not kh_exist_int64(table, k):
            k = kh_put_int64(table, obj, &ret)
            uniques[j] = obj
            j += 1
            # Py_INCREF(<object> obj)

    kh_destroy_int64(table)

    return np.sort(uniques[:j])

cdef class StringHashTable:

    cdef:
        kh_str_t *table

    def __init__(self, size_hint=1):
        if size_hint is not None:
            kh_resize_str(self.table, size_hint)

    def __cinit__(self):
        self.table = kh_init_str()

    def __dealloc__(self):
        kh_destroy_str(self.table)

    cdef inline int check_type(self, object val):
        return PyString_Check(val)

    cpdef get_item(self, object val):
        cdef khiter_t k
        k = kh_get_str(self.table, PyString_AsString(val))
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, object key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val
        for i in range(iterations):
            k = kh_get_str(self.table, PyString_AsString(key))
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, object key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret
            char* buf

        buf = PyString_AsString(key)

        k = kh_put_str(self.table, buf, &ret)
        self.table.keys[k] = key
        if kh_exist_str(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def get_indexer(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels = np.empty(n, dtype=np.int32)
            char *buf
            int32_t *resbuf = <int32_t*> labels.data
            khiter_t k
            kh_str_t *table = self.table

        for i in range(n):
            buf = PyString_AsString(values[i])
            k = kh_get_str(table, buf)
            if k != table.n_buckets:
                resbuf[i] = table.vals[k]
            else:
                resbuf[i] = -1
        return labels

    def factorize(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels = np.empty(n, dtype=np.int32)
            ndarray[int32_t] counts = np.empty(n, dtype=np.int32)
            dict reverse = {}
            Py_ssize_t idx, count = 0
            int ret
            object val
            char *buf
            khiter_t k

        for i in range(n):
            val = values[i]
            buf = PyString_AsString(val)
            k = kh_get_str(self.table, buf)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_str(self.table, buf, &ret)
                # print 'putting %s, %s' % (val, count)
                if not ret:
                    kh_del_str(self.table, k)

                self.table.vals[k] = count
                reverse[count] = val
                labels[i] = count
                counts[count] = 1
                count += 1

        # return None
        return reverse, labels, counts[:count].copy()

cdef class Int32HashTable:

    cdef:
        kh_int32_t *table

    def __init__(self, size_hint=1):
        if size_hint is not None:
            kh_resize_int32(self.table, size_hint)

    def __cinit__(self):
        self.table = kh_init_int32()

    def __dealloc__(self):
        kh_destroy_int32(self.table)

    cdef inline int check_type(self, object val):
        return PyString_Check(val)

    cpdef get_item(self, int32_t val):
        cdef khiter_t k
        k = kh_get_int32(self.table, val)
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, int32_t key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val
        for i in range(iterations):
            k = kh_get_int32(self.table, val)
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, int32_t key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret

        k = kh_put_int32(self.table, key, &ret)
        self.table.keys[k] = key
        if kh_exist_int32(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def map_locations(self, ndarray[int32_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            int32_t val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_put_int32(self.table, val, &ret)
            # print 'putting %s, %s' % (val, count)
            self.table.vals[k] = i

    def lookup_locations(self, ndarray[int32_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            int32_t val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        for i in range(n):
            val = values[i]
            k = kh_get_int32(self.table, val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def factorize(self, ndarray[int32_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels = np.empty(n, dtype=np.int32)
            ndarray[int32_t] counts = np.empty(n, dtype=np.int32)
            dict reverse = {}
            Py_ssize_t idx, count = 0
            int ret
            int32_t val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_get_int32(self.table, val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_int32(self.table, val, &ret)
                if not ret:
                    kh_del_int32(self.table, k)
                self.table.vals[k] = count
                reverse[count] = val
                labels[i] = count
                counts[count] = 1
                count += 1

        # return None
        return reverse, labels, counts[:count].copy()

cdef class Int64HashTable:

    cdef:
        kh_int64_t *table

    def __init__(self, size_hint=1):
        if size_hint is not None:
            kh_resize_int64(self.table, size_hint)

    def __cinit__(self):
        self.table = kh_init_int64()

    def __dealloc__(self):
        kh_destroy_int64(self.table)

    cdef inline int check_type(self, object val):
        return PyString_Check(val)

    cpdef get_item(self, int64_t val):
        cdef khiter_t k
        k = kh_get_int64(self.table, val)
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, int64_t key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val
        for i in range(iterations):
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, int64_t key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret

        k = kh_put_int64(self.table, key, &ret)
        self.table.keys[k] = key
        if kh_exist_int64(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def map_locations(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            int64_t val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_put_int64(self.table, val, &ret)
            # print 'putting %s, %s' % (val, count)
            self.table.vals[k] = i

    def lookup_locations(self, ndarray[int64_t] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            int64_t val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def factorize(self, ndarray[object] values):
        reverse = {}
        labels, counts = self.get_labels(values, reverse, 0)
        return reverse, labels, counts

    def get_labels(self, ndarray[int64_t] values, list uniques,
                   Py_ssize_t count_prior):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = count_prior
            int ret
            int64_t val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count_prior + n, dtype=np.int32)

        for i in range(n):
            val = values[i]
            k = kh_get_int64(self.table, val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_int64(self.table, val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

cdef class PyObjectHashTable:

    cdef:
        kh_pymap_t *table

    def __init__(self, size_hint=1):
        self.table = kh_init_pymap()
        kh_resize_pymap(self.table, size_hint)

    def __dealloc__(self):
        if self.table is not NULL:
            self.destroy()

    cpdef destroy(self):
        kh_destroy_pymap(self.table)
        self.table = NULL

    cpdef get_item(self, object val):
        cdef khiter_t k
        k = kh_get_pymap(self.table, <PyObject*>val)
        if k != self.table.n_buckets:
            return self.table.vals[k]
        else:
            raise KeyError(val)

    def get_iter_test(self, object key, Py_ssize_t iterations):
        cdef Py_ssize_t i, val
        for i in range(iterations):
            k = kh_get_pymap(self.table, <PyObject*>key)
            if k != self.table.n_buckets:
                val = self.table.vals[k]

    cpdef set_item(self, object key, Py_ssize_t val):
        cdef:
            khiter_t k
            int ret
            char* buf

        k = kh_put_pymap(self.table, <PyObject*>key, &ret)
        # self.table.keys[k] = key
        if kh_exist_pymap(self.table, k):
            self.table.vals[k] = val
        else:
            raise KeyError(key)

    def map_locations(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            object val
            khiter_t k

        for i in range(n):
            val = values[i]
            k = kh_put_pymap(self.table, <PyObject*>val, &ret)
            # print 'putting %s, %s' % (val, count)
            self.table.vals[k] = i

    def lookup_locations(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            object val
            khiter_t k
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        for i in range(n):
            val = values[i]
            k = kh_get_pymap(self.table, <PyObject*>val)
            if k != self.table.n_buckets:
                locs[i] = self.table.vals[k]
            else:
                locs[i] = -1

        return locs

    def lookup_locations2(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            int ret
            object val
            khiter_t k
            long hval
            ndarray[int32_t] locs = np.empty(n, dtype='i4')

        # for i in range(n):
        #     val = values[i]
            # hval = PyObject_Hash(val)
            # k = kh_get_pymap(self.table, <PyObject*>val)

        return locs

    def unique(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels = np.empty(n, dtype=np.int32)
            ndarray[int32_t] counts = np.empty(n, dtype=np.int32)
            dict reverse = {}
            Py_ssize_t idx, count = 0
            int ret
            object val
            khiter_t k
            list uniques = []

        for i in range(n):
            val = values[i]
            k = kh_get_pymap(self.table, <PyObject*>val)
            if k == self.table.n_buckets:
                k = kh_put_pymap(self.table, <PyObject*>val, &ret)
                uniques.append(val)

        return uniques

    def factorize(self, ndarray[object] values):
        reverse = {}
        labels, counts = self.get_labels(values, reverse, 0)
        return reverse, labels, counts

    cpdef get_labels(self, ndarray[object] values, list uniques,
                     Py_ssize_t count_prior):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = count_prior
            int ret
            object val
            khiter_t k

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count_prior + n, dtype=np.int32)

        for i in range(n):
            val = values[i]
            k = kh_get_pymap(self.table, <PyObject*>val)
            if k != self.table.n_buckets:
                idx = self.table.vals[k]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                k = kh_put_pymap(self.table, <PyObject*>val, &ret)
                self.table.vals[k] = count
                uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

cdef class Factorizer:

    cdef public:
        PyObjectHashTable table
        list uniques
        Py_ssize_t count

    def __init__(self, size_hint):
        self.table = PyObjectHashTable(size_hint)
        self.uniques = []
        self.count = 0

    def get_count(self):
        return self.count

    def factorize(self, ndarray[object] values, sort=False):
        labels, counts = self.table.get_labels(values, self.uniques,
                                               self.count)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts

cdef class Int64Factorizer:

    cdef public:
        Int64HashTable table
        list uniques
        Py_ssize_t count

    def __init__(self, size_hint):
        self.table = Int64HashTable(size_hint)
        self.uniques = []
        self.count = 0

    def get_count(self):
        return self.count

    def factorize(self, ndarray[int64_t] values, sort=False):
        labels, counts = self.table.get_labels(values, self.uniques,
                                               self.count)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts

cdef class DictFactorizer:

    cdef public:
        dict table
        list uniques
        Py_ssize_t count

    def __init__(self, table=None, uniques=None):
        if table is None:
            self.table = {}
        else:
            self.table = table

        if uniques is None:
            self.uniques = []
            self.count = 0
        else:
            self.uniques = uniques
            self.count = len(uniques)

    def get_count(self):
        return self.count

    def get_labels(self, ndarray[object] values):
        cdef:
            Py_ssize_t i, n = len(values)
            ndarray[int32_t] labels
            ndarray[int32_t] counts
            Py_ssize_t idx, count = self.count
            int ret
            object val

        labels = np.empty(n, dtype=np.int32)
        counts = np.empty(count + n, dtype=np.int32)

        for i in range(n):
            val = values[i]

            if val in self.table:
                idx = self.table[val]
                labels[i] = idx
                counts[idx] = counts[idx] + 1
            else:
                self.table[val] = count
                self.uniques.append(val)
                labels[i] = count
                counts[count] = 1
                count += 1

        return labels, counts[:count].copy()

    def factorize(self, ndarray[object] values, sort=False):
        labels, counts = self.get_labels(values)

        # sort on
        if sort:
            sorter = list_to_object_array(self.uniques).argsort()
            reverse_indexer = np.empty(len(sorter), dtype=np.int32)
            reverse_indexer.put(sorter, np.arange(len(sorter)))

            labels = reverse_indexer.take(labels)
            counts = counts.take(sorter)

        self.count = len(counts)
        return labels, counts


def lookup_locations2(ndarray[object] values):
    cdef:
        Py_ssize_t i, n = len(values)
        int ret
        object val
        khiter_t k
        long hval
        ndarray[int32_t] locs = np.empty(n, dtype='i4')

    # for i in range(n):
    #     val = values[i]
        # hval = PyObject_Hash(val)
        # k = kh_get_pymap(self.table, <PyObject*>val)

    return locs

