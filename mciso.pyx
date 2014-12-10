#cython: profile=False
#cython: boundscheck=False
#cython: cdivision=True

# NOTE: order of slow fonction to be optimize/multithreaded: kdtreesearching , kdtreecreating , linksolving 

cimport cython
from time import clock
from libc.math cimport sin , ceil , floor , fabs
from cython.parallel import parallel , prange , threadid
from libc.stdlib cimport malloc , realloc, free , rand , srand

ctypedef int (*f_type)(Cell)nogil

cdef extern from *:
    int INT_MIN
    int INT_MAX
    long LONG_MIN
    long LONG_MAX
    float FLT_MIN
    float FLT_MAX

cdef extern from "stdlib.h":
    ctypedef void const_void "const void"
    void qsort(void *base, int nmemb, int size,int(*compar)(const_void *, const_void *)) nogil
    

cdef int *cytrimem = NULL
cdef int *cytrinum = NULL
cdef float ****cytriangles = NULL
cdef float *cysend = NULL
cdef Particle *cypar = NULL
cdef unsigned long long cyparnum = 0

cdef int *edgetable=[0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
                                0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
                                0x190, 0x99 , 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
                                0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
                                0x230, 0x339, 0x33 , 0x13a, 0x636, 0x73f, 0x435, 0x53c,
                                0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
                                0x3a0, 0x2a9, 0x1a3, 0xaa , 0x7a6, 0x6af, 0x5a5, 0x4ac,
                                0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
                                0x460, 0x569, 0x663, 0x76a, 0x66 , 0x16f, 0x265, 0x36c,
                                0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
                                0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff , 0x3f5, 0x2fc,
                                0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
                                0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55 , 0x15c,
                                0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
                                0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc ,
                                0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
                                0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
                                0xcc , 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
                                0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c,
                                0x15c, 0x55 , 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
                                0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc,
                                0x2fc, 0x3f5, 0xff , 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
                                0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c,
                                0x36c, 0x265, 0x16f, 0x66 , 0x76a, 0x663, 0x569, 0x460,
                                0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac,
                                0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa , 0x1a3, 0x2a9, 0x3a0,
                                0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
                                0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33 , 0x339, 0x230,
                                0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c,
                                0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99 , 0x190,
                                0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c,
                                0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0]
                              
                              
cdef int **tritable = [[-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 1, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 8, 3, 9, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 2, 10, 0, 2, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [2, 8, 3, 2, 10, 8, 10, 9, 8, -1, -1, -1, -1, -1, -1, -1],
                    [3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 11, 2, 8, 11, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 9, 0, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 11, 2, 1, 9, 11, 9, 8, 11, -1, -1, -1, -1, -1, -1, -1],
                    [3, 10, 1, 11, 10, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 10, 1, 0, 8, 10, 8, 11, 10, -1, -1, -1, -1, -1, -1, -1],
                    [3, 9, 0, 3, 11, 9, 11, 10, 9, -1, -1, -1, -1, -1, -1, -1],
                    [9, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 3, 0, 7, 3, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 1, 9, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 1, 9, 4, 7, 1, 7, 3, 1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 4, 7, 3, 0, 4, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1],
                    [9, 2, 10, 9, 0, 2, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1],
                    [2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1, -1, -1, -1],
                    [8, 4, 7, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [11, 4, 7, 11, 2, 4, 2, 0, 4, -1, -1, -1, -1, -1, -1, -1],
                    [9, 0, 1, 8, 4, 7, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1],
                    [4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1, -1, -1, -1],
                    [3, 10, 1, 3, 11, 10, 7, 8, 4, -1, -1, -1, -1, -1, -1, -1],
                    [1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1, -1, -1, -1],
                    [4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1, -1, -1, -1],
                    [4, 7, 11, 4, 11, 9, 9, 11, 10, -1, -1, -1, -1, -1, -1, -1],
                    [9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 5, 4, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 5, 4, 1, 5, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [8, 5, 4, 8, 3, 5, 3, 1, 5, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 0, 8, 1, 2, 10, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1],
                    [5, 2, 10, 5, 4, 2, 4, 0, 2, -1, -1, -1, -1, -1, -1, -1],
                    [2, 10, 5, 3, 2, 5, 3, 5, 4, 3, 4, 8, -1, -1, -1, -1],
                    [9, 5, 4, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 11, 2, 0, 8, 11, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1],
                    [0, 5, 4, 0, 1, 5, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1],
                    [2, 1, 5, 2, 5, 8, 2, 8, 11, 4, 8, 5, -1, -1, -1, -1],
                    [10, 3, 11, 10, 1, 3, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1],
                    [4, 9, 5, 0, 8, 1, 8, 10, 1, 8, 11, 10, -1, -1, -1, -1],
                    [5, 4, 0, 5, 0, 11, 5, 11, 10, 11, 0, 3, -1, -1, -1, -1],
                    [5, 4, 8, 5, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1],
                    [9, 7, 8, 5, 7, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 3, 0, 9, 5, 3, 5, 7, 3, -1, -1, -1, -1, -1, -1, -1],
                    [0, 7, 8, 0, 1, 7, 1, 5, 7, -1, -1, -1, -1, -1, -1, -1],
                    [1, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 7, 8, 9, 5, 7, 10, 1, 2, -1, -1, -1, -1, -1, -1, -1],
                    [10, 1, 2, 9, 5, 0, 5, 3, 0, 5, 7, 3, -1, -1, -1, -1],
                    [8, 0, 2, 8, 2, 5, 8, 5, 7, 10, 5, 2, -1, -1, -1, -1],
                    [2, 10, 5, 2, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1],
                    [7, 9, 5, 7, 8, 9, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1],
                    [9, 5, 7, 9, 7, 2, 9, 2, 0, 2, 7, 11, -1, -1, -1, -1],
                    [2, 3, 11, 0, 1, 8, 1, 7, 8, 1, 5, 7, -1, -1, -1, -1],
                    [11, 2, 1, 11, 1, 7, 7, 1, 5, -1, -1, -1, -1, -1, -1, -1],
                    [9, 5, 8, 8, 5, 7, 10, 1, 3, 10, 3, 11, -1, -1, -1, -1],
                    [5, 7, 0, 5, 0, 9, 7, 11, 0, 1, 0, 10, 11, 10, 0, -1],
                    [11, 10, 0, 11, 0, 3, 10, 5, 0, 8, 0, 7, 5, 7, 0, -1],
                    [11, 10, 5, 7, 11, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 0, 1, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 8, 3, 1, 9, 8, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1],
                    [1, 6, 5, 2, 6, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 6, 5, 1, 2, 6, 3, 0, 8, -1, -1, -1, -1, -1, -1, -1],
                    [9, 6, 5, 9, 0, 6, 0, 2, 6, -1, -1, -1, -1, -1, -1, -1],
                    [5, 9, 8, 5, 8, 2, 5, 2, 6, 3, 2, 8, -1, -1, -1, -1],
                    [2, 3, 11, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [11, 0, 8, 11, 2, 0, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1],
                    [0, 1, 9, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1],
                    [5, 10, 6, 1, 9, 2, 9, 11, 2, 9, 8, 11, -1, -1, -1, -1],
                    [6, 3, 11, 6, 5, 3, 5, 1, 3, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 11, 0, 11, 5, 0, 5, 1, 5, 11, 6, -1, -1, -1, -1],
                    [3, 11, 6, 0, 3, 6, 0, 6, 5, 0, 5, 9, -1, -1, -1, -1],
                    [6, 5, 9, 6, 9, 11, 11, 9, 8, -1, -1, -1, -1, -1, -1, -1],
                    [5, 10, 6, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 3, 0, 4, 7, 3, 6, 5, 10, -1, -1, -1, -1, -1, -1, -1],
                    [1, 9, 0, 5, 10, 6, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1],
                    [10, 6, 5, 1, 9, 7, 1, 7, 3, 7, 9, 4, -1, -1, -1, -1],
                    [6, 1, 2, 6, 5, 1, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 5, 5, 2, 6, 3, 0, 4, 3, 4, 7, -1, -1, -1, -1],
                    [8, 4, 7, 9, 0, 5, 0, 6, 5, 0, 2, 6, -1, -1, -1, -1],
                    [7, 3, 9, 7, 9, 4, 3, 2, 9, 5, 9, 6, 2, 6, 9, -1],
                    [3, 11, 2, 7, 8, 4, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1],
                    [5, 10, 6, 4, 7, 2, 4, 2, 0, 2, 7, 11, -1, -1, -1, -1],
                    [0, 1, 9, 4, 7, 8, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1],
                    [9, 2, 1, 9, 11, 2, 9, 4, 11, 7, 11, 4, 5, 10, 6, -1],
                    [8, 4, 7, 3, 11, 5, 3, 5, 1, 5, 11, 6, -1, -1, -1, -1],
                    [5, 1, 11, 5, 11, 6, 1, 0, 11, 7, 11, 4, 0, 4, 11, -1],
                    [0, 5, 9, 0, 6, 5, 0, 3, 6, 11, 6, 3, 8, 4, 7, -1],
                    [6, 5, 9, 6, 9, 11, 4, 7, 9, 7, 11, 9, -1, -1, -1, -1],
                    [10, 4, 9, 6, 4, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 10, 6, 4, 9, 10, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1],
                    [10, 0, 1, 10, 6, 0, 6, 4, 0, -1, -1, -1, -1, -1, -1, -1],
                    [8, 3, 1, 8, 1, 6, 8, 6, 4, 6, 1, 10, -1, -1, -1, -1],
                    [1, 4, 9, 1, 2, 4, 2, 6, 4, -1, -1, -1, -1, -1, -1, -1],
                    [3, 0, 8, 1, 2, 9, 2, 4, 9, 2, 6, 4, -1, -1, -1, -1],
                    [0, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [8, 3, 2, 8, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1],
                    [10, 4, 9, 10, 6, 4, 11, 2, 3, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 2, 2, 8, 11, 4, 9, 10, 4, 10, 6, -1, -1, -1, -1],
                    [3, 11, 2, 0, 1, 6, 0, 6, 4, 6, 1, 10, -1, -1, -1, -1],
                    [6, 4, 1, 6, 1, 10, 4, 8, 1, 2, 1, 11, 8, 11, 1, -1],
                    [9, 6, 4, 9, 3, 6, 9, 1, 3, 11, 6, 3, -1, -1, -1, -1],
                    [8, 11, 1, 8, 1, 0, 11, 6, 1, 9, 1, 4, 6, 4, 1, -1],
                    [3, 11, 6, 3, 6, 0, 0, 6, 4, -1, -1, -1, -1, -1, -1, -1],
                    [6, 4, 8, 11, 6, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [7, 10, 6, 7, 8, 10, 8, 9, 10, -1, -1, -1, -1, -1, -1, -1],
                    [0, 7, 3, 0, 10, 7, 0, 9, 10, 6, 7, 10, -1, -1, -1, -1],
                    [10, 6, 7, 1, 10, 7, 1, 7, 8, 1, 8, 0, -1, -1, -1, -1],
                    [10, 6, 7, 10, 7, 1, 1, 7, 3, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 6, 1, 6, 8, 1, 8, 9, 8, 6, 7, -1, -1, -1, -1],
                    [2, 6, 9, 2, 9, 1, 6, 7, 9, 0, 9, 3, 7, 3, 9, -1],
                    [7, 8, 0, 7, 0, 6, 6, 0, 2, -1, -1, -1, -1, -1, -1, -1],
                    [7, 3, 2, 6, 7, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [2, 3, 11, 10, 6, 8, 10, 8, 9, 8, 6, 7, -1, -1, -1, -1],
                    [2, 0, 7, 2, 7, 11, 0, 9, 7, 6, 7, 10, 9, 10, 7, -1],
                    [1, 8, 0, 1, 7, 8, 1, 10, 7, 6, 7, 10, 2, 3, 11, -1],
                    [11, 2, 1, 11, 1, 7, 10, 6, 1, 6, 7, 1, -1, -1, -1, -1],
                    [8, 9, 6, 8, 6, 7, 9, 1, 6, 11, 6, 3, 1, 3, 6, -1],
                    [0, 9, 1, 11, 6, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [7, 8, 0, 7, 0, 6, 3, 11, 0, 11, 6, 0, -1, -1, -1, -1],
                    [7, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 0, 8, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 1, 9, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [8, 1, 9, 8, 3, 1, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1],
                    [10, 1, 2, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, 3, 0, 8, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1],
                    [2, 9, 0, 2, 10, 9, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1],
                    [6, 11, 7, 2, 10, 3, 10, 8, 3, 10, 9, 8, -1, -1, -1, -1],
                    [7, 2, 3, 6, 2, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [7, 0, 8, 7, 6, 0, 6, 2, 0, -1, -1, -1, -1, -1, -1, -1],
                    [2, 7, 6, 2, 3, 7, 0, 1, 9, -1, -1, -1, -1, -1, -1, -1],
                    [1, 6, 2, 1, 8, 6, 1, 9, 8, 8, 7, 6, -1, -1, -1, -1],
                    [10, 7, 6, 10, 1, 7, 1, 3, 7, -1, -1, -1, -1, -1, -1, -1],
                    [10, 7, 6, 1, 7, 10, 1, 8, 7, 1, 0, 8, -1, -1, -1, -1],
                    [0, 3, 7, 0, 7, 10, 0, 10, 9, 6, 10, 7, -1, -1, -1, -1],
                    [7, 6, 10, 7, 10, 8, 8, 10, 9, -1, -1, -1, -1, -1, -1, -1],
                    [6, 8, 4, 11, 8, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 6, 11, 3, 0, 6, 0, 4, 6, -1, -1, -1, -1, -1, -1, -1],
                    [8, 6, 11, 8, 4, 6, 9, 0, 1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 4, 6, 9, 6, 3, 9, 3, 1, 11, 3, 6, -1, -1, -1, -1],
                    [6, 8, 4, 6, 11, 8, 2, 10, 1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, 3, 0, 11, 0, 6, 11, 0, 4, 6, -1, -1, -1, -1],
                    [4, 11, 8, 4, 6, 11, 0, 2, 9, 2, 10, 9, -1, -1, -1, -1],
                    [10, 9, 3, 10, 3, 2, 9, 4, 3, 11, 3, 6, 4, 6, 3, -1],
                    [8, 2, 3, 8, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1],
                    [0, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 9, 0, 2, 3, 4, 2, 4, 6, 4, 3, 8, -1, -1, -1, -1],
                    [1, 9, 4, 1, 4, 2, 2, 4, 6, -1, -1, -1, -1, -1, -1, -1],
                    [8, 1, 3, 8, 6, 1, 8, 4, 6, 6, 10, 1, -1, -1, -1, -1],
                    [10, 1, 0, 10, 0, 6, 6, 0, 4, -1, -1, -1, -1, -1, -1, -1],
                    [4, 6, 3, 4, 3, 8, 6, 10, 3, 0, 3, 9, 10, 9, 3, -1],
                    [10, 9, 4, 6, 10, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 9, 5, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, 4, 9, 5, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1],
                    [5, 0, 1, 5, 4, 0, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1],
                    [11, 7, 6, 8, 3, 4, 3, 5, 4, 3, 1, 5, -1, -1, -1, -1],
                    [9, 5, 4, 10, 1, 2, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1],
                    [6, 11, 7, 1, 2, 10, 0, 8, 3, 4, 9, 5, -1, -1, -1, -1],
                    [7, 6, 11, 5, 4, 10, 4, 2, 10, 4, 0, 2, -1, -1, -1, -1],
                    [3, 4, 8, 3, 5, 4, 3, 2, 5, 10, 5, 2, 11, 7, 6, -1],
                    [7, 2, 3, 7, 6, 2, 5, 4, 9, -1, -1, -1, -1, -1, -1, -1],
                    [9, 5, 4, 0, 8, 6, 0, 6, 2, 6, 8, 7, -1, -1, -1, -1],
                    [3, 6, 2, 3, 7, 6, 1, 5, 0, 5, 4, 0, -1, -1, -1, -1],
                    [6, 2, 8, 6, 8, 7, 2, 1, 8, 4, 8, 5, 1, 5, 8, -1],
                    [9, 5, 4, 10, 1, 6, 1, 7, 6, 1, 3, 7, -1, -1, -1, -1],
                    [1, 6, 10, 1, 7, 6, 1, 0, 7, 8, 7, 0, 9, 5, 4, -1],
                    [4, 0, 10, 4, 10, 5, 0, 3, 10, 6, 10, 7, 3, 7, 10, -1],
                    [7, 6, 10, 7, 10, 8, 5, 4, 10, 4, 8, 10, -1, -1, -1, -1],
                    [6, 9, 5, 6, 11, 9, 11, 8, 9, -1, -1, -1, -1, -1, -1, -1],
                    [3, 6, 11, 0, 6, 3, 0, 5, 6, 0, 9, 5, -1, -1, -1, -1],
                    [0, 11, 8, 0, 5, 11, 0, 1, 5, 5, 6, 11, -1, -1, -1, -1],
                    [6, 11, 3, 6, 3, 5, 5, 3, 1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 10, 9, 5, 11, 9, 11, 8, 11, 5, 6, -1, -1, -1, -1],
                    [0, 11, 3, 0, 6, 11, 0, 9, 6, 5, 6, 9, 1, 2, 10, -1],
                    [11, 8, 5, 11, 5, 6, 8, 0, 5, 10, 5, 2, 0, 2, 5, -1],
                    [6, 11, 3, 6, 3, 5, 2, 10, 3, 10, 5, 3, -1, -1, -1, -1],
                    [5, 8, 9, 5, 2, 8, 5, 6, 2, 3, 8, 2, -1, -1, -1, -1],
                    [9, 5, 6, 9, 6, 0, 0, 6, 2, -1, -1, -1, -1, -1, -1, -1],
                    [1, 5, 8, 1, 8, 0, 5, 6, 8, 3, 8, 2, 6, 2, 8, -1],
                    [1, 5, 6, 2, 1, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 3, 6, 1, 6, 10, 3, 8, 6, 5, 6, 9, 8, 9, 6, -1],
                    [10, 1, 0, 10, 0, 6, 9, 5, 0, 5, 6, 0, -1, -1, -1, -1],
                    [0, 3, 8, 5, 6, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [10, 5, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [11, 5, 10, 7, 5, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [11, 5, 10, 11, 7, 5, 8, 3, 0, -1, -1, -1, -1, -1, -1, -1],
                    [5, 11, 7, 5, 10, 11, 1, 9, 0, -1, -1, -1, -1, -1, -1, -1],
                    [10, 7, 5, 10, 11, 7, 9, 8, 1, 8, 3, 1, -1, -1, -1, -1],
                    [11, 1, 2, 11, 7, 1, 7, 5, 1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, 1, 2, 7, 1, 7, 5, 7, 2, 11, -1, -1, -1, -1],
                    [9, 7, 5, 9, 2, 7, 9, 0, 2, 2, 11, 7, -1, -1, -1, -1],
                    [7, 5, 2, 7, 2, 11, 5, 9, 2, 3, 2, 8, 9, 8, 2, -1],
                    [2, 5, 10, 2, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1],
                    [8, 2, 0, 8, 5, 2, 8, 7, 5, 10, 2, 5, -1, -1, -1, -1],
                    [9, 0, 1, 5, 10, 3, 5, 3, 7, 3, 10, 2, -1, -1, -1, -1],
                    [9, 8, 2, 9, 2, 1, 8, 7, 2, 10, 2, 5, 7, 5, 2, -1],
                    [1, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 7, 0, 7, 1, 1, 7, 5, -1, -1, -1, -1, -1, -1, -1],
                    [9, 0, 3, 9, 3, 5, 5, 3, 7, -1, -1, -1, -1, -1, -1, -1],
                    [9, 8, 7, 5, 9, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [5, 8, 4, 5, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1],
                    [5, 0, 4, 5, 11, 0, 5, 10, 11, 11, 3, 0, -1, -1, -1, -1],
                    [0, 1, 9, 8, 4, 10, 8, 10, 11, 10, 4, 5, -1, -1, -1, -1],
                    [10, 11, 4, 10, 4, 5, 11, 3, 4, 9, 4, 1, 3, 1, 4, -1],
                    [2, 5, 1, 2, 8, 5, 2, 11, 8, 4, 5, 8, -1, -1, -1, -1],
                    [0, 4, 11, 0, 11, 3, 4, 5, 11, 2, 11, 1, 5, 1, 11, -1],
                    [0, 2, 5, 0, 5, 9, 2, 11, 5, 4, 5, 8, 11, 8, 5, -1],
                    [9, 4, 5, 2, 11, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [2, 5, 10, 3, 5, 2, 3, 4, 5, 3, 8, 4, -1, -1, -1, -1],
                    [5, 10, 2, 5, 2, 4, 4, 2, 0, -1, -1, -1, -1, -1, -1, -1],
                    [3, 10, 2, 3, 5, 10, 3, 8, 5, 4, 5, 8, 0, 1, 9, -1],
                    [5, 10, 2, 5, 2, 4, 1, 9, 2, 9, 4, 2, -1, -1, -1, -1],
                    [8, 4, 5, 8, 5, 3, 3, 5, 1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 4, 5, 1, 0, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [8, 4, 5, 8, 5, 3, 9, 0, 5, 0, 3, 5, -1, -1, -1, -1],
                    [9, 4, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 11, 7, 4, 9, 11, 9, 10, 11, -1, -1, -1, -1, -1, -1, -1],
                    [0, 8, 3, 4, 9, 7, 9, 11, 7, 9, 10, 11, -1, -1, -1, -1],
                    [1, 10, 11, 1, 11, 4, 1, 4, 0, 7, 4, 11, -1, -1, -1, -1],
                    [3, 1, 4, 3, 4, 8, 1, 10, 4, 7, 4, 11, 10, 11, 4, -1],
                    [4, 11, 7, 9, 11, 4, 9, 2, 11, 9, 1, 2, -1, -1, -1, -1],
                    [9, 7, 4, 9, 11, 7, 9, 1, 11, 2, 11, 1, 0, 8, 3, -1],
                    [11, 7, 4, 11, 4, 2, 2, 4, 0, -1, -1, -1, -1, -1, -1, -1],
                    [11, 7, 4, 11, 4, 2, 8, 3, 4, 3, 2, 4, -1, -1, -1, -1],
                    [2, 9, 10, 2, 7, 9, 2, 3, 7, 7, 4, 9, -1, -1, -1, -1],
                    [9, 10, 7, 9, 7, 4, 10, 2, 7, 8, 7, 0, 2, 0, 7, -1],
                    [3, 7, 10, 3, 10, 2, 7, 4, 10, 1, 10, 0, 4, 0, 10, -1],
                    [1, 10, 2, 8, 7, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 9, 1, 4, 1, 7, 7, 1, 3, -1, -1, -1, -1, -1, -1, -1],
                    [4, 9, 1, 4, 1, 7, 0, 8, 1, 8, 7, 1, -1, -1, -1, -1],
                    [4, 0, 3, 7, 4, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [4, 8, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [9, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 0, 9, 3, 9, 11, 11, 9, 10, -1, -1, -1, -1, -1, -1, -1],
                    [0, 1, 10, 0, 10, 8, 8, 10, 11, -1, -1, -1, -1, -1, -1, -1],
                    [3, 1, 10, 11, 3, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 2, 11, 1, 11, 9, 9, 11, 8, -1, -1, -1, -1, -1, -1, -1],
                    [3, 0, 9, 3, 9, 11, 1, 2, 9, 2, 11, 9, -1, -1, -1, -1],
                    [0, 2, 11, 8, 0, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [3, 2, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [2, 3, 8, 2, 8, 10, 10, 8, 9, -1, -1, -1, -1, -1, -1, -1],
                    [9, 10, 2, 0, 9, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [2, 3, 8, 2, 8, 10, 0, 1, 8, 1, 10, 8, -1, -1, -1, -1],
                    [1, 10, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [1, 3, 8, 9, 1, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 9, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [0, 3, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
                    [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]]

cdef float scalarfield(Point pos,unsigned int *par,int parnum)nogil:
    #'''
    global cypar,cyparnum
    cdef int i = 0
    cdef int ii = 0
    cdef float dist = 0.0
    cdef float x = 0.0
    cdef float y = 0.0
    cdef float z = 0.0
    cdef float a = 1000000000.0
    cdef float b = 0
    #for i in range(parnum):
        #print "  ",par[i]
    for i in range(parnum):
        ii = par[i]
        x = pos.loc[0] - cypar[ii].loc[0]
        y = pos.loc[1] - cypar[ii].loc[1]
        z = pos.loc[2] - cypar[ii].loc[2]
        dist = x*x+y*y+z*z
        b = dist - (cypar[ii].size * cypar[ii].size)
        if b < a:
            a = b
    return a
    #'''
    '''        
    cdef float m = 2 #distance between spheres
    cdef float a
    cdef float b
    cdef float c
    cdef float csq
    a= 1.0/(1+(pos.loc[0]-m)*(pos.loc[0]-m)+pos.loc[1]*pos.loc[1]+pos.loc[2]*pos.loc[2])
    b= 1.0/(1+(pos.loc[0]+m)*(pos.loc[0]+m)+pos.loc[1]*pos.loc[1]+pos.loc[2]*pos.loc[2])
    c= 0.5*(sin(6*pos.loc[0])+sin(6*pos.loc[2]))
    csq=c**10
    return (a+b)-csq
    '''
    
    #return pos.loc[0]*pos.loc[0]+pos.loc[1]*pos.loc[1]+pos.loc[2]*pos.loc[2] 
 
 
cdef void polygonise(float *cycornervalues,Point *cycornerpos,float isolevel,int blocknum)nogil:
    global edgetable,tritable,cytriangles,cytrimem,cytrinum

    cdef int i = 0
    cdef int cubeindex = 0
    cdef Point *cyvertlist = NULL
    
    #cornervalues = [0] * 8
    #cornerpos = [0] * 8
    #for i in range(8):
        #cornervalues[i] = cycornervalues[i]
        #cornerpos[i] = [cycornerpos[i][0],cycornerpos[i][1],cycornerpos[i][2]]
       
        #   Determine the index into the edge table which
        #   tells us which vertices are inside of the surface

    if cycornervalues[0] < isolevel: cubeindex = cubeindex | 1
    if cycornervalues[1] < isolevel: cubeindex = cubeindex | 2
    if cycornervalues[2] < isolevel: cubeindex = cubeindex | 4
    if cycornervalues[3] < isolevel: cubeindex = cubeindex | 8
    if cycornervalues[4] < isolevel: cubeindex = cubeindex | 16
    if cycornervalues[5] < isolevel: cubeindex = cubeindex | 32
    if cycornervalues[6] < isolevel: cubeindex = cubeindex | 64
    if cycornervalues[7] < isolevel: cubeindex = cubeindex | 128
       
    # Cube is entirely in/out of the surface
    if edgetable[cubeindex] == 0:
        return #[]
       
    #vertlist=[]
    cyvertlist = <Point *>malloc( 12 * cython.sizeof(Point) )
        #vertlist.append([0,0,0])
        
        # Find the vertices where the surface intersects the cube
    if (edgetable[cubeindex] & 1):    vertexinterp(&cyvertlist[0],isolevel,cycornerpos[0],cycornerpos[1],cycornervalues[0],cycornervalues[1])
    if (edgetable[cubeindex] & 2):    vertexinterp(&cyvertlist[1],isolevel,cycornerpos[1],cycornerpos[2],cycornervalues[1],cycornervalues[2])
    if (edgetable[cubeindex] & 4):    vertexinterp(&cyvertlist[2],isolevel,cycornerpos[2],cycornerpos[3],cycornervalues[2],cycornervalues[3])
    if (edgetable[cubeindex] & 8):    vertexinterp(&cyvertlist[3],isolevel,cycornerpos[3],cycornerpos[0],cycornervalues[3],cycornervalues[0])
    if (edgetable[cubeindex] & 16):   vertexinterp(&cyvertlist[4],isolevel,cycornerpos[4],cycornerpos[5],cycornervalues[4],cycornervalues[5])
    if (edgetable[cubeindex] & 32):   vertexinterp(&cyvertlist[5],isolevel,cycornerpos[5],cycornerpos[6],cycornervalues[5],cycornervalues[6])
    if (edgetable[cubeindex] & 64):   vertexinterp(&cyvertlist[6],isolevel,cycornerpos[6],cycornerpos[7],cycornervalues[6],cycornervalues[7])
    if (edgetable[cubeindex] & 128):  vertexinterp(&cyvertlist[7],isolevel,cycornerpos[7],cycornerpos[4],cycornervalues[7],cycornervalues[4])
    if (edgetable[cubeindex] & 256):  vertexinterp(&cyvertlist[8],isolevel,cycornerpos[0],cycornerpos[4],cycornervalues[0],cycornervalues[4])
    if (edgetable[cubeindex] & 512):  vertexinterp(&cyvertlist[9],isolevel,cycornerpos[1],cycornerpos[5],cycornervalues[1],cycornervalues[5])
    if (edgetable[cubeindex] & 1024): vertexinterp(&cyvertlist[10],isolevel,cycornerpos[2],cycornerpos[6],cycornervalues[2],cycornervalues[6])
    if (edgetable[cubeindex] & 2048): vertexinterp(&cyvertlist[11],isolevel,cycornerpos[3],cycornerpos[7],cycornervalues[3],cycornervalues[7])
    
    #for i in xrange(12):
        #vertlist[i][0] = cyvertlist[i][0]
        #vertlist[i][1] = cyvertlist[i][1]
        #vertlist[i][2] = cyvertlist[i][2]
    
    #Create the triangle
    #triangles = []
    #for (i=0;triTable[cubeindex][i]!=-1;i+=3) {
    i=0
    #print blocknum
    while tritable[cubeindex][i] != -1:
        cytriangles[blocknum][cytrinum[blocknum]] = <float **>malloc( 3 * cython.sizeof(double) )
        for ii in range(3):
            cytriangles[blocknum][cytrinum[blocknum]][ii] = <float *>malloc( 3 * cython.sizeof(float) )
        cytriangles[blocknum][cytrinum[blocknum]][0][0] = cyvertlist[tritable[cubeindex][i]].loc[0]
        cytriangles[blocknum][cytrinum[blocknum]][0][1] = cyvertlist[tritable[cubeindex][i]].loc[1]
        cytriangles[blocknum][cytrinum[blocknum]][0][2] = cyvertlist[tritable[cubeindex][i]].loc[2]
        
        cytriangles[blocknum][cytrinum[blocknum]][1][0] = cyvertlist[tritable[cubeindex][i+1]].loc[0]
        cytriangles[blocknum][cytrinum[blocknum]][1][1] = cyvertlist[tritable[cubeindex][i+1]].loc[1]
        cytriangles[blocknum][cytrinum[blocknum]][1][2] = cyvertlist[tritable[cubeindex][i+1]].loc[2]
        
        cytriangles[blocknum][cytrinum[blocknum]][2][0] = cyvertlist[tritable[cubeindex][i+2]].loc[0]
        cytriangles[blocknum][cytrinum[blocknum]][2][1] = cyvertlist[tritable[cubeindex][i+2]].loc[1]
        cytriangles[blocknum][cytrinum[blocknum]][2][2] = cyvertlist[tritable[cubeindex][i+2]].loc[2]
        cytrinum[blocknum] += 1
        
        if cytrinum[blocknum] >= cytrimem[blocknum] - 2:
            cytrimem[blocknum] = <int>(<double>cytrimem[blocknum] * 1.25)
            cytriangles[blocknum] = <float ***>realloc(cytriangles[blocknum],cytrimem[blocknum] * cython.sizeof(double) )
        
        #triangles.append([vertlist[tritable[cubeindex][i  ]],vertlist[tritable[cubeindex][i+1]],vertlist[tritable[cubeindex][i+2]]])
        
        i+=3

    free(cyvertlist)
    cyvertlist = NULL  
    #return #triangles
 
cdef void vertexinterp(Point *cyvertlist,float isolevel,Point p1,Point p2,float valp1,float valp2)nogil:
    if (fabs(isolevel-valp1) < 0.00001):
        cyvertlist.loc[0] = p1.loc[0]
        cyvertlist.loc[1] = p1.loc[1]
        cyvertlist.loc[2] = p1.loc[2]
        return
    if (fabs(isolevel-valp2) < 0.00001):
        cyvertlist.loc[0] = p2.loc[0]
        cyvertlist.loc[1] = p2.loc[1]
        cyvertlist.loc[2] = p2.loc[2]
        return
    if (fabs(valp1-valp2) < 0.00001):
        cyvertlist.loc[0] = p1.loc[0]
        cyvertlist.loc[1] = p1.loc[1]
        cyvertlist.loc[2] = p1.loc[2]
        return
    cdef float mu
    cdef float *p = [0,0,0]
    mu = ((isolevel - valp1) / (valp2 - valp1))
    cyvertlist.loc[0] = p1.loc[0] + mu * (p2.loc[0] - p1.loc[0])
    cyvertlist.loc[1] = p1.loc[1] + mu * (p2.loc[1] - p1.loc[1])
    cyvertlist.loc[2] = p1.loc[2] + mu * (p2.loc[2] - p1.loc[2])
 
    #return
 
 
cdef void arange(float *result,float start, float stop, float step)nogil:
    cdef float r = start
    cdef int icount = 0
    while r < stop:
        result[icount] = r
        r += step
        icount += 1
    #return
 
cdef void cellloop(Point *cyresult,float *p0,float *p1,float *r,int *cyres,int cellr)nogil:

    cdef float *xresult = NULL
    cdef float *yresult = NULL
    cdef float *zresult = NULL
    cdef int ix = 0
    cdef int iy = 0
    cdef int iz = 0
    cdef int i = 0
    xresult = <float *>malloc( (<int>(((p1[0] - p0[0]) / r[0]) + 1)) * cython.sizeof(float) )
    yresult = <float *>malloc( (<int>(((p1[1] - p0[1]) / r[1]) + 1)) * cython.sizeof(float) )
    zresult = <float *>malloc( (<int>(((p1[2] - p0[2]) / r[2]) + 1)) * cython.sizeof(float) )
    arange(&zresult[0],p0[2],p1[2],r[2])
    for iz in xrange(cyres[2]):
        arange(&yresult[0],p0[1],p1[1],r[1])
        for iy in xrange(cyres[1]):
            arange(&xresult[0],p0[0],p1[0],r[0])
            for ix in xrange(cyres[0]):
                cyresult[i].loc[0] = xresult[ix]
                cyresult[i].loc[1] = yresult[iy]
                cyresult[i].loc[2] = zresult[iz]
                i += 1

    free(xresult)
    free(yresult)
    free(zresult)
    xresult = NULL
    yresult = NULL
    zresult = NULL
    #return
   
cdef void cornerloop(Point *cyresult,float x,float y,float z)nogil:
    cdef int i = 0
    cdef int ii = 0
    cdef float *cx = [0,0,0,0]
    cdef float *cy = [0,0,0,0]
    cdef float *cz = [0,0]
    
    cz[0] = 0
    cz[1] = z
    for icz in xrange(2):
        cy[0] = 0
        cy[1] = y
        cy[2] = y
        cy[3] = 0
        cx[0] = 0
        cx[1] = 0
        cx[2] = x
        cx[3] = x
        for i in xrange(4):
            cyresult[ii].loc[0] = cx[i]
            cyresult[ii].loc[1] = cy[i]
            cyresult[ii].loc[2] = cz[icz]
            ii += 1
    #return

cpdef isosurface(p0,p1,resolution,float isolevel,ploc,psize,int div):
    global cytriangles,cytrimem,cytrinum,cypar,cyparnum
    
    cdef float *cyp0 = [p0[0],p0[1],p0[2]]
    cdef float *cyp1 = [p1[0],p1[1],p1[2]]
    cdef int *cyres = [resolution[0],resolution[1],resolution[2]]
    cdef long cellr = <unsigned long>(resolution[0] * resolution[1] * resolution[2])
    cdef long tri = 0
    cdef long vert = 0
    cdef long pt = 0
    cdef long i = 0
    cdef long ii = 0
    cdef int ix = 0
    cdef int iy = 0
    cdef int iz = 0
    cdef float x = 0
    cdef float y = 0
    cdef float z = 0
    #cdef int div = 2
    cdef int blocknum = div * div * div
    cdef float timer1 = 0
    cdef float timer2 = 0
    
    timer2 = clock()
    cyparnum = len(psize)
    cypar = <Particle *>malloc( (cyparnum + 1) * cython.sizeof(Particle) )
    cytrimem = <int *>malloc( blocknum * cython.sizeof(int) )
    cytrinum = <int *>malloc( blocknum * cython.sizeof(int) )
    cytriangles = <float ****>malloc( blocknum * cython.sizeof(double) )
    for i in range(blocknum):
        cytrimem[i] = 40
        cytrinum[i] = 0
        cytriangles[i] = <float ***>malloc( cytrimem[i] * cython.sizeof(double) )
        
    #print psize
    for i in xrange(cyparnum):
        cypar[i].id = i
        cypar[i].size = psize[i]
        cypar[i].loc[0] = ploc[i][0]
        cypar[i].loc[1] = ploc[i][1]
        cypar[i].loc[2] = ploc[i][2]
        #print i
    
    #**** NEED TO BE DYNAMIC
    cdef Point *cyrange0 = NULL
    cdef Point *cyrange1 = NULL
    cyrange0 = <Point *>malloc( blocknum * cython.sizeof(Point) )
    cyrange1 = <Point *>malloc( blocknum * cython.sizeof(Point) )
    #cdef float cyrange0[8][3]
    #cdef float cyrange1[8][3]
    
    i = 0
    
    x = fabs(cyp0[0] - cyp1[0])/div
    y = fabs(cyp0[1] - cyp1[1])/div
    z = fabs(cyp0[2] - cyp1[2])/div
    
    for ix in range(div):
        for iy in range(div):
            for iz in range(div):
                cyrange0[i].loc[0] = cyp0[0] + (x * ix)
                cyrange0[i].loc[1] = cyp0[1] + (y * iy)
                cyrange0[i].loc[2] = cyp0[2] + (z * iz)
                
                cyrange1[i].loc[0] = cyp0[0] + (x * (ix+1))
                cyrange1[i].loc[1] = cyp0[1] + (y * (iy+1))
                cyrange1[i].loc[2] = cyp0[2] + (z * (iz+1))
                #print "(",cyrange0[i][0],cyrange0[i][1],cyrange0[i][2],")(",cyrange1[i][0],cyrange1[i][1],cyrange1[i][2],")"
                i += 1
    cyres[0] = cyres[0] / div
    cyres[1] = cyres[1] / div
    cyres[2] = cyres[2] / div
    i = 10
    
    timer2 = clock() - timer2
    timer1 = clock()
    
    with nogil:
        for i in prange(blocknum,schedule='dynamic',chunksize=1,num_threads=12):
            build(cyrange0[i].loc,cyrange1[i].loc,cyres,cellr,isolevel,i)
    
    #for i in range(blocknum):
            #build(cyrange0[i].loc,cyrange1[i].loc,cyres,cellr,isolevel,i)
    #build(cyp0,cyp1,cyres,cellr,isolevel)
    
    print ' Get Particles:',timer2,'s'
    print ' calculate geometry:',clock() - timer1,'s'
    timer1 = clock()
    
    totaltri = 0
    for i in range(blocknum):
        totaltri += cytrinum[i]
    
    tmptriangles = [666.666] * totaltri * 3 * 3
    i = 0
    for ii in range(blocknum):
        for tri in range(cytrinum[ii]):
            for vert in range(3):
                for pt in range(3):
                    tmptriangles[i] = cytriangles[ii][tri][vert][pt]
                    i += 1
                    #print i,cytrinum * 3 * 3
    #print(i,cytrinum * 3 * 3,cytrinum)

    for ii in range(blocknum):
        for tri in range(cytrinum[ii]):
            for i in range(3):
                free(cytriangles[ii][tri][i])
                cytriangles[ii][tri][i] = NULL
            free(cytriangles[ii][tri])
            cytriangles[ii][tri] = NULL
        free(cytriangles[ii])
        cytriangles[ii] = NULL
    free(cytriangles)
    cytriangles = NULL
    free(cytrimem)
    cytrimem = NULL
    free(cytrinum)
    cytrinum = NULL
    free(cypar)
    cypar = NULL
    cyparnum = 0

    print ' send to pyarray:',clock() - timer1,'s'
    return tmptriangles

    
cdef void build(float *cyp0,float *cyp1,int *cyres,long cellr,float isolevel,int blocknum)nogil:
    global cytriangles,cytrimem,cytrinum,cypar,cyparnum
    
    #cdef float *cyp0 = [p0[0],p0[1],p0[2]]
    #cdef float *cyp1 = [p1[0],p1[1],p1[2]]
    #cdef int *cyres = [resolution[0],resolution[1],resolution[2]]
    #cdef int cellr = <int>(resolution[0] * resolution[1] * resolution[2])
    
    cdef long i = 0
    cdef long ii = 0
    cdef long ix = 0
    cdef long iy = 0
    cdef long iz = 0
    cdef float x = 0
    cdef float y = 0
    cdef float z = 0
    cdef float cx = 0
    cdef float cy = 0
    cdef float cz = 0
    cdef float *r = [0,0,0]
    cdef float sx = 0
    cdef float sy = 0
    cdef float sz = 0
    cdef long tz = 0
    cdef long ty = 0
    cdef long tx = 0
    cdef float ttz = 0
    cdef float tty = 0
    cdef float ttx = 0
    cdef float xsize = 0
    cdef float ysize = 0
    cdef float zsize = 0
    cdef long xmin = 0
    cdef long xmax = 0
    cdef long ymin = 0
    cdef long ymax = 0
    cdef long zmin = 0
    cdef long zmax = 0
    cdef unsigned long id = 0
    cdef float timer1 = 0
    cdef float timer2 = 0
    cdef float timer3 = 0
    
    cdef Point *cornerpos = NULL
    cdef float *cornervalues = NULL
    cdef Point *celll = NULL
    cdef Point *cornerl = NULL
    
    
    cornerpos = <Point *>malloc( 8 * cython.sizeof(Point) )
    cornerl = <Point *>malloc( 8 * cython.sizeof(Point) )
    
    #celll = <Point *>malloc( cellr * cython.sizeof(Point) )
    
    cornervalues = <float *>malloc( 8 * cython.sizeof(float) )
    
    for i in range(3):
        r[i] = (cyp1[i]-cyp0[i])/cyres[i]

    #cellloop(&celll[0],cyp0,cyp1,r,cyres,cellr)
    
    #print 'ceil 2.25 = ', ceil(2.25)
    #print 'floor 2.25 = ', floor(2.25)
    
    with gil:
        timer1 = clock()
    cdef long cellmem = 4
    cdef long cellnum = 0
    cdef long ncellnum = 0
    cdef Cell *cells = <Cell *>malloc( cellmem * cython.sizeof(Cell) )
    sx = fabs((cyp1[0] - cyp0[0])) / cyres[0]
    sy = fabs((cyp1[1] - cyp0[1])) / cyres[1]
    sz = fabs((cyp1[2] - cyp0[2])) / cyres[2]
    #test = []
    #'''
    cdef long test = 0
    for i in range(cyparnum):
        x = (cypar[i].loc[0] - cyp0[0]) / sx
        y = (cypar[i].loc[1] - cyp0[1]) / sy
        z = (cypar[i].loc[2] - cyp0[2]) / sz
        xsize = cypar[i].size / sx
        ysize = cypar[i].size / sy
        zsize = cypar[i].size / sz
        xmin = <long>(floor(x - xsize)-1)
        xmax = <long>(ceil(x + xsize)+1)
        ymin = <long>(floor(y - ysize)-1)
        ymax = <long>(ceil(y + ysize)+1)
        zmin = <long>(floor(z - zsize)-1)
        zmax = <long>(ceil(z + zsize)+1)

        if xmax < 0:
            continue
        if xmin > cyres[0]:
            continue
        if ymax < 0:
            continue
        if ymin > cyres[1]:
            continue
        if zmax < 0:
            continue
        if zmin > cyres[2]:
            continue

        if xmin < 0:
            xmin = 0
        if xmax > cyres[0]:
            xmax = cyres[0]
        if ymin < 0:
            ymin = 0
        if ymax > cyres[1]:
            ymax = cyres[1]
        if zmin < 0:
            zmin = 0
        if zmax > cyres[2]:
            zmax = cyres[2]
        #print xmin,xmax,ymin,ymax,zmin,zmax
        test += 1
        for iz in xrange(zmin,zmax):
            for iy in xrange(ymin,ymax):
                for ix in xrange(xmin,xmax):
                    #test.append(int((z*(cyres[0]*cyres[0]))+(y*cyres[1])+x))
                    id = <unsigned long>((iz*(cyres[1]*cyres[0]))+(iy*cyres[0])+ix) 
                    #print 'hit'
                    #if arraysearch(id,cells,cellnum) == -1:
                    cells[cellnum].id = id
                    cells[cellnum].parmem = 1
                    cells[cellnum].parnum = 0
                    cells[cellnum].par = <unsigned int *>malloc( cells[cellnum].parmem * cython.sizeof(int) )
                    cells[cellnum].par[0] = cypar[i].id
                    cellnum += 1
                    if cellnum >= cellmem - 2:
                        cellmem = <int>(<double>cellmem * 1.25)
                        cells = <Cell *>realloc(cells,cellmem * cython.sizeof(Cell) )
    #print blocknum,':',test
    #for i in range(cellnum): 
        #print "id:",cells[i].id,"parnum",cells[i].parnum
        #print "  ", cells[i].par[0]
    with gil:
        timer1 = clock() - timer1
        timer2 = clock()
    quick_sort(cells,cellnum,idparam)
    for i in range(cellnum):
        if cells[i].id != cells[i+1].id:
            cells[ncellnum].id = cells[i].id
            cells[ncellnum].par[cells[ncellnum].parnum] = cells[i].par[0]
            cells[ncellnum].parnum += 1
            ncellnum += 1
        else:
            cells[ncellnum].par[cells[ncellnum].parnum] = cells[i].par[0]
            cells[ncellnum].parnum += 1
            if cells[ncellnum].parnum >= cells[ncellnum].parmem-1:
                cells[ncellnum].parmem = <int>(<double>cells[ncellnum].parmem * 1.25) + 1
                cells[ncellnum].par = <unsigned int *>realloc(cells[ncellnum].par,cells[ncellnum].parmem * cython.sizeof(int) )
    with gil:
        timer2 = clock() - timer2
        timer3 = clock()
    #print INT_MIN
    #print INT_MAX
    #print LONG_MIN
    #print LONG_MAX
    #print FLT_MIN
    #print FLT_MAX
    #print '---'
    #for i in range(ncellnum): 
        #print cells[i].id,cells[i].parnum
        #for ii in range(cells[i].parnum):
            #print "  ", cells[i].par[ii]
    
    #print cells[0]
    #test = set(test)
    #test = tuple(test)
    #print (test)
    #'''
    #for i in xrange(cellr):
    for i in range(ncellnum):
        id = cells[i].id
        #x = celll[i].loc[0]
        #y = celll[i].loc[1]
        #z = celll[i].loc[2]
        #'''
        sx = fabs((cyp1[0] - cyp0[0])) / cyres[0]
        sy = fabs((cyp1[1] - cyp0[1])) / cyres[1]
        sz = fabs((cyp1[2] - cyp0[2])) / cyres[2]
        tz = int(id/(cyres[1]*cyres[0]))  #(((int(i/(cyres[2]*cyres[2]))) * sz) + cyp0[2])
        ty = int((id-(tz*(cyres[1]*cyres[0])))/cyres[0])
        tx = int((id-(tz*(cyres[1]*cyres[0])))-(ty * cyres[0]))
        ttz = ((tz * sz) + cyp0[2])
        tty = ((ty * sy) + cyp0[1])
        ttx = ((tx * sx) + cyp0[0])
        x = ttx
        y = tty
        z = ttz
        #'''
        #print i,':',x,y,z," | ",tx,ty,tz," | ",ttx,tty,ttz
        cornerloop(&cornerl[0],r[0],r[1],r[2])
        for ii in xrange(8):
            cx = cornerl[ii].loc[0]
            cy = cornerl[ii].loc[1]
            cz = cornerl[ii].loc[2]
            cornerpos[ii].loc[0] = x+cx
            cornerpos[ii].loc[1] = y+cy
            cornerpos[ii].loc[2] = z+cz
            cornervalues[ii] = scalarfield(cornerpos[ii],cells[i].par,cells[i].parnum)
        polygonise(cornervalues,cornerpos,isolevel,blocknum)
    

    free(cornerl)
    cornerl = NULL
    free(cornerpos)
    cornerpos = NULL
    free(cornervalues)
    cornervalues = NULL
    #free(celll)
    #celll = NULL
    for i in range(cellnum):
        free(cells[i].par)
        cells[i].par = NULL
        cells[i].parnum = 0
        cells[i].parmem = 1
    free(cells)
    cells = NULL
    with gil:
        timer3 = clock() - timer3
    with gil:
        print "CPU No:",blocknum," cells:",ncellnum,"/",cellnum,' findvox:',timer1,'s  optivox:',timer2,'s  geo:',timer3,'s'
    
    return


cdef float xparam(Point a)nogil:
    return a.loc[0]
    
cdef float yparam(Point a)nogil:
    return a.loc[1]
    
cdef float zparam(Point a)nogil:
    return a.loc[2]

    
cdef int idparam(Cell a)nogil:
    return a.id

    
cdef void quick_sort(Cell *a,long long n,f_type func)nogil:
    if (n < 2):
        return
    cdef Cell t
    cdef double p = func(a[n / 2])#a[n / 2].loc[0]
    cdef Cell *l = a
    cdef Cell *r = a + n - 1
    while l <= r:
        if func(l[0]) < p:
            l += 1
            continue
        
        if func(r[0]) > p:
            r -= 1
            continue #// we need to check the condition (l <= r) every time we change the value of l or r
        
        t = l[0]
        l[0] = r[0]
        #l[0], r[0] = r[0], l[0]  # suggested by stephan to remove temp variable t but slower
        l += 1
        r[0] = t
        r -= 1
    
    quick_sort(a, r - a + 1,func)
    quick_sort(l, a + n - l,func)

    
cdef int bsearch(Point *A,int n, float x,char searchFirst)nogil:
    cdef int low = 0
    cdef int high = n-1
    cdef int result = -1
    cdef int mid = 0
    
    while low <= high:
        mid = (low+high)/2
        if A[mid].loc[0] == x:
            result = mid
            if searchFirst == 1:
                high = mid-1
            else:
                low = mid+1
        elif x < A[mid].loc[0]:
            high = mid-1
        else:
            low = mid+1
    return result


cdef int arraysearch(int element,Cell *array,int len)nogil:
    cdef int i = 0
    for i in xrange(len):
        if element == array[i].id:
            return i
    return -1
    
cdef struct Point:
    unsigned long id
    float loc[3]

cdef struct Particle:
    unsigned long id
    float size
    float loc[3]

cdef struct Cell:
    unsigned long id
    unsigned int *par
    int parnum
    int parmem
