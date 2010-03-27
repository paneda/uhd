//
// Copyright 2010 Ettus Research LLC
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// asize_t with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#include <uhd/device.hpp>
#include <uhd/types/dict.hpp>
#include <uhd/utils/assert.hpp>
#include <uhd/utils/static.hpp>
#include <boost/foreach.hpp>
#include <boost/format.hpp>
#include <boost/weak_ptr.hpp>
#include <boost/functional/hash.hpp>
#include <boost/tuple/tuple.hpp>
#include <stdexcept>
#include <algorithm>

using namespace uhd;

/***********************************************************************
 * Helper Functions
 **********************************************************************/
/*!
 * Make a device hash that maps 1 to 1 with a device address.
 * The hash will be used to identify created devices.
 * \param dev_addr the device address
 * \return the hash number
 */
static size_t hash_device_addr(
    const device_addr_t &dev_addr
){
    //sort the keys of the device address
    std::vector<std::string> keys = dev_addr.get_keys();
    std::sort(keys.begin(), keys.end());

    //combine the hashes of sorted keys/value pairs
    size_t hash = 0;
    BOOST_FOREACH(std::string key, keys){
        boost::hash_combine(hash, key);
        boost::hash_combine(hash, dev_addr[key]);
    }
    return hash;
}

/***********************************************************************
 * Registration
 **********************************************************************/
typedef boost::tuple<device::discover_t, device::make_t> dev_fcn_reg_t;

// instantiate the device function registry container
UHD_SINGLETON_FCN(std::vector<dev_fcn_reg_t>, get_dev_fcn_regs)

void device::register_device(
    const discover_t &discover,
    const make_t &make
){
    //std::cout << "registering device" << std::endl;
    get_dev_fcn_regs().push_back(dev_fcn_reg_t(discover, make));
}

/***********************************************************************
 * Discover
 **********************************************************************/
device_addrs_t device::discover(const device_addr_t &hint){
    device_addrs_t device_addrs;

    BOOST_FOREACH(dev_fcn_reg_t fcn, get_dev_fcn_regs()){
        device_addrs_t discovered_addrs = fcn.get<0>()(hint);
        device_addrs.insert(
            device_addrs.begin(),
            discovered_addrs.begin(),
            discovered_addrs.end()
        );
    }

    return device_addrs;
}

/***********************************************************************
 * Make
 **********************************************************************/
device::sptr device::make(const device_addr_t &hint, size_t which){
    typedef boost::tuple<device_addr_t, make_t> dev_addr_make_t;
    std::vector<dev_addr_make_t> dev_addr_makers;

    BOOST_FOREACH(dev_fcn_reg_t fcn, get_dev_fcn_regs()){
        BOOST_FOREACH(device_addr_t dev_addr, fcn.get<0>()(hint)){
            //copy keys that were in hint but not in dev_addr
            //this way, we can pass additional transport arguments
            BOOST_FOREACH(std::string key, hint.get_keys()){
                if (not dev_addr.has_key(key)) dev_addr[key] = hint[key];
            }
            //append the discovered address and its factory function
            dev_addr_makers.push_back(dev_addr_make_t(dev_addr, fcn.get<1>()));
        }
    }

    //check that we found any devices
    if (dev_addr_makers.size() == 0){
        throw std::runtime_error(str(
            boost::format("No devices found for ----->\n%s") % hint.to_string()
        ));
    }

    //check that the which index is valid
    if (dev_addr_makers.size() <= which){
        throw std::runtime_error(str(
            boost::format("No device at index %d for ----->\n%s") % which % hint.to_string()
        ));
    }

    //create a unique hash for the device address
    device_addr_t dev_addr; make_t maker;
    boost::tie(dev_addr, maker) = dev_addr_makers.at(which);
    size_t dev_hash = hash_device_addr(dev_addr);
    //std::cout << boost::format("Hash: %u") % dev_hash << std::endl;

    //map device address hash to created devices
    static uhd::dict<size_t, boost::weak_ptr<device> > hash_to_device;

    //try to find an existing device
    try{
        ASSERT_THROW(hash_to_device.has_key(dev_hash));
        ASSERT_THROW(not hash_to_device[dev_hash].expired());
        return hash_to_device[dev_hash].lock();
    }
    //create and register a new device
    catch(const uhd::assert_error &){
        device::sptr dev = maker(dev_addr);
        hash_to_device[dev_hash] = dev;
        return dev;
    }
}
