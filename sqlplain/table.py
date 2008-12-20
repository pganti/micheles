import sys, string
from sqlplain import util
from sqlplain.namedtuple import namedtuple
from sqlplain.connection import connmethod

def tolist(fields):
    'Convert a comma or space separated string (or an iterable) to a list'
    if isinstance(fields, list):
        return fields
    elif isinstance(fields, basestring):
        fields = fields.replace(',', ' ').split()
    return list(fields)

def tabletuple(name, kfields, dfields):
    """
    Returns a namedtuple with attributes ._kfields, ._dfields and properties
    ._kvalues, .dvalues. This is needed to send records to a database table
    with a primary key
    """
    kfields, dfields = tolist(kfields), tolist(dfields)
    ttuple = namedtuple(name, kfields + dfields)
    ttuple._ktuple = ktuple = namedtuple(name + '_key', kfields)
    ttuple._dtuple = dtuple = namedtuple(name + '_data', dfields)
    ttuple._kfields = ktuple._fields
    ttuple._dfields = dtuple._fields
    ttuple._kvalues = property(
        lambda self: ktuple(*[getattr(self, n) for n in self._kfields]))
    ttuple._dvalues = property(
        lambda self: dtuple(*[getattr(self, n) for n in self._dfields]))
    return ttuple

# note: the methods of the Table classes
# are completely external to the class except for the .conn attribute

def insert(ttuple):
    "Return a procedure inserting a row or a dictionary into a table"
    name = ttuple.__name__
    csfields = ','.join(ttuple._fields)
    qmarks = ','.join('?'*len(ttuple._fields))
    templ = 'INSERT INTO %s (%s) VALUES (%s)' % (name, csfields, qmarks)
    def insert_row(conn, row=None, **kw):
        row = row or {}
        if isinstance(row, dict):
            row.update(kw)
            row = ttuple(**row)
        return conn.execute(templ, row)
    insert_row.__doc__ = insert_row.templ = templ
    return insert_row

def select(ttuple):
    """
    Returns a function with signature (conn, key) - where key can be
    a dictionary or a tabletuple - returning a single row.
    """
    name = ttuple.__name__
    csfields = ','.join(ttuple._fields)
    clause = ' AND '.join('%s=?' % field for field in ttuple._kfields)
    templ = 'SELECT %s FROM %s WHERE %s' % (csfields, name, clause)
    def select_row(conn, row=None, **kw):
        row = row or {}
        if isinstance(row, dict):
            row.update(kw)
            row = ttuple._ktuple(**row)        
        res = conn.execute(templ, row, ttuple)
        if not res:
            raise KeyError('Missing record for %s' % str(row))
        elif len(res) > 1:
            raise RuntimeError('Got %s instead of a single row' % res)
        return res[0]
    select_row.__doc__ = select_row.templ = templ
    return select_row

def delete(ttuple):
    "Return a procedure inserting a row or a dictionary into a table"
    name = ttuple.__name__
    clause = ' AND '.join('%s=?' % field for field in ttuple._kfields)
    templ = 'DELETE FROM %s WHERE %s' % (name, clause)
    def delete_row(conn, row=None, **kw):
        row = row or {}
        if isinstance(row, dict):
            row.update(kw)
            row = ttuple._ktuple(**row)        
        return conn.execute(templ, row, ttuple)
    delete_row.__doc__ = delete_row.templ = templ
    return delete_row

def update(ttuple):
    "Returns a procedure updating a row"
    name = ttuple.__name__
    where = ' AND '.join('%s=?' % field for field in ttuple._kfields)
    templ = string.Template('UPDATE %s SET $set WHERE %s' % (name, where))
    def update_row(conn, row=None, **kw):
        if row is None:
            row = {}
        elif hasattr(row, '_asdict'):
            row = row._asdict()
        row.update(kw)
        kvalues, dvalues, dfields = [], [], []
        for f, v in row.iteritems():
            if f in ttuple._kfields:
                kvalues.append(v)
            else:
                dvalues.append(v)
                dfields.append(f)
        sql = templ.substitute(set=', '.join('%s=?' % f for f in dfields))
        return conn.execute(sql, dvalues + kvalues)
    update_row.__doc__ = update_row.templ = templ
    return update_row

def update_or_insert(ttuple):
    "Returns a procedure updating or inserting a row"
    up = update(ttuple)
    ins = insert(ttuple)
    def update_or_insert_row(conn, row=None, **kw):
        n = up(conn, row, **kw)
        if n == 0:
            n = ins(conn, row, **kw)
        return n
    update_or_insert_row.__doc__ = update_or_insert_row.templ = None
    return update_or_insert_row

class DTable(object):
    """
    A simple table class for database tables without a primary key.
    The only methods are insert_row, bulk_insert, delete, truncate, select.
    """
    @classmethod
    def type(cls, name, fields):
        "Ex. Insert = DTable.type('book', 'serial', 'title author')"
        tt = namedtuple(name, fields)
        def bulk_insert(conn, file, sep='\t'):
            'Populate a table by reading a file-like object'
            return util._call('bulk_insert', conn, file, name, sep)
        dic = dict(
            tt = tt,
            name = tt.__name__,
            insert_row = connmethod(insert(tt)),
            bulk_insert = connmethod(bulk_insert),
            )
        return type(name.capitalize(), (cls,), dic)

    @classmethod
    def object(cls, conn, name):
        "Ex. insert = DTable.object(mydb, 'book')"
        fields = util.get_fields(conn, name)
        return cls.type(name, fields)(conn)

    def __init__(self, conn):
        self.tt # raise AttributeError if not initialized correctly
        self.conn = conn

    def select(self, clause=''):
        fields = ', '.join(self.tt._fields)
        return self.conn.execute(
            'SELECT %s FROM %s %s' % (fields, self.name, clause),
            ntuple=self.tt)

    def delete(self, clause=''):
        return self.conn.execute('DELETE FROM ' + self.name + ' ' + clause)

    def truncate(self):
        return self.conn.execute('TRUNCATE TABLE %s' % self.name)


class KTable(DTable):
    @classmethod
    def type(cls, name, kfields, dfields):
        "Ex. Book = Table.type('book', 'serial', 'title author')"
        tt = tabletuple(name, kfields, dfields)
        d = dict(tt=tt, name=name)
        for nam in ('insert', 'delete', 'select', 'update', 'update_or_insert'):
            func = globals()[nam](tt)
            cmethod = connmethod(func)
            d[nam + '_row'] = cmethod
        return type(name.capitalize(), (cls,), d)

    @classmethod
    def object(cls, conn, name):
        "Ex. book = Table.object(mydb, 'book')"
        kfields = util.get_kfields(conn, name)
        dfields = util.get_dfields(conn, name)
        return cls.type(name, kfields, dfields)(conn)

    def __init__(self, conn):
        self.tt # raise AttributeError if not initialized correctly
        self.conn = conn

    def __contains__(self, key):
        pass
    
    def keys(self):
        kfields = ', '.join(self.tt._kfields)
        return self.conn.execute(
            'SELECT %s FROM %s' % (kfields, self.name))

if __name__ == '__main__':
    tt = tabletuple('tt', 'x y', 'a,b')(1, 2, 3, 4)
    print tt._kvalues, tt._dvalues
    print tt.__class__.mro()

    Book = KTable.type('book', 'pubdate', 'title author')
    from sqlplain import lazyconnect
    conn = lazyconnect('srs_dev')
    book = Book(conn)
    #help(Book.select_row)
    #help(Book.insert_row)
    #help(Book.delete_row)
    #help(Book.update_row)
    #help(Book.update_or_insert_row)
